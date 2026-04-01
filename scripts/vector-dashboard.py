#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Vector dashboard — 3-tab view of the AI log pipeline.

Tabs:
  Pipeline  — live Vector component stats (GraphQL API)
  Projects  — event counts grouped by cwd / repo
  Analytics — source breakdown, message types, top tools

Usage:
  uv run ./scripts/vector-dashboard.py          # default port 8765
  uv run ./scripts/vector-dashboard.py --port 9000
  uv run ./scripts/vector-dashboard.py --sink ~/logs/ai/vector
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import threading
import time
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

DEFAULT_PORT = 8765
DEFAULT_SINK = Path.home() / "logs" / "ai" / "vector"
VECTOR_API = "http://127.0.0.1:9598/graphql"

_PIPELINE_QUERY = """
{
  sources { edges { node {
    componentId componentType
    metrics {
      sentEventsTotal { sentEventsTotal }
      receivedBytesTotal { receivedBytesTotal }
    }
  }}}
  transforms { edges { node {
    componentId componentType
    metrics { sentEventsTotal { sentEventsTotal } }
  }}}
  sinks { edges { node {
    componentId componentType
    metrics {
      sentEventsTotal { sentEventsTotal }
      sentBytesTotal { sentBytesTotal }
    }
  }}}
}
"""


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

def open_log(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8", errors="ignore")
    return path.open("rt", encoding="utf-8", errors="ignore")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


# ---------------------------------------------------------------------------
# Pipeline tab — Vector GraphQL
# ---------------------------------------------------------------------------

def fetch_pipeline() -> dict:
    try:
        payload = json.dumps({"query": _PIPELINE_QUERY}).encode()
        req = urllib.request.Request(
            VECTOR_API, data=payload,
            headers={"Content-Type": "application/json"}, method="POST",
        )
        with urllib.request.urlopen(req, timeout=3) as r:
            body = json.loads(r.read())
        if "errors" in body:
            return {"online": False, "error": body["errors"][0]["message"]}
        d = body.get("data") or {}

        def extract(section: str) -> list:
            bytes_field = "receivedBytesTotal" if section == "sources" else "sentBytesTotal"
            rows = []
            for edge in (d.get(section) or {}).get("edges") or []:
                node = edge.get("node") or {}
                m = node.get("metrics") or {}
                rows.append({
                    "id": node.get("componentId", "?"),
                    "kind": section.rstrip("s"),
                    "events": int((m.get("sentEventsTotal") or {}).get("sentEventsTotal") or 0),
                    "bytes": int((m.get(bytes_field) or {}).get(bytes_field) or 0),
                })
            return rows

        components = extract("sources") + extract("transforms") + extract("sinks")
        return {
            "online": True,
            "generated_at": now_iso(),
            "components": components,
            "total_events": sum(c["events"] for c in components if c["kind"] == "source"),
            "total_bytes": sum(c["bytes"] for c in components if c["kind"] == "source"),
        }
    except Exception as exc:
        return {"online": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# Sink parser — shared scan used by Projects + Analytics
# ---------------------------------------------------------------------------

class SinkData:
    """Parsed view of ~/logs/ai/vector/*.jsonl files, with mtime-based cache."""

    def __init__(self, sink_root: Path):
        self.sink_root = sink_root
        self._lock = threading.Lock()
        self._mtime: float = 0.0
        self._data: dict | None = None

    def current_mtime(self) -> float:
        try:
            return max(p.stat().st_mtime for p in self.sink_root.glob("*.jsonl*"))
        except (ValueError, OSError):
            return 0.0

    def get(self) -> dict:
        with self._lock:
            mtime = self.current_mtime()
            if self._data and mtime <= self._mtime:
                return self._data
            self._data = self._parse()
            self._mtime = mtime
            return self._data

    def _parse(self) -> dict:
        source_counts: dict[str, int] = defaultdict(int)
        type_counts: dict[str, int] = defaultdict(int)
        tool_counts: dict[str, int] = defaultdict(int)
        # Per-source tool breakdowns
        tools_by_source: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        projects: dict[str, dict] = {}
        total = 0
        files_scanned = 0

        # Source-specific analytics
        codex_stats: dict = {"sessions": 0, "models": defaultdict(int),
                             "payload_types": defaultdict(int)}
        opencode_stats: dict = {"sessions": set(), "services": defaultdict(int),
                                "methods": defaultdict(int)}
        cursor_stats: dict = {"audit_tools": defaultdict(int), "total_tokens": 0,
                              "cost_tools": defaultdict(int), "diary_sessions": 0,
                              "diary_tool_calls": 0}

        for shard in sorted(self.sink_root.glob("*.jsonl*")):
            files_scanned += 1
            try:
                with open_log(shard) as f:
                    for line in f:
                        try:
                            e = json.loads(line)
                        except Exception:
                            continue
                        total += 1
                        src = e.get("source") or ""
                        source_counts[src] += 1

                        role = e.get("role") or e.get("type") or ""
                        if role:
                            type_counts[role] += 1

                        cwd = e.get("cwd") or e.get("directory") or ""
                        if cwd:
                            cwd_norm = re.sub(r"/\.worktrees/[^/]+", "", cwd)
                            cwd_norm = cwd_norm.replace(str(Path.home()), "~")
                            proj = projects.setdefault(cwd_norm, {
                                "cwd": cwd_norm,
                                "events": 0,
                                "last_ts": "",
                                "branch": "",
                                "sources": defaultdict(int),
                            })
                            proj["events"] += 1
                            proj["sources"][src] += 1
                            ts = e.get("ts") or e.get("timestamp") or ""
                            if ts > proj["last_ts"]:
                                proj["last_ts"] = ts
                            branch = e.get("gitBranch") or ""
                            if branch and branch != "HEAD":
                                proj["branch"] = branch

                        # --- Tool extraction per source ---

                        # Claude Code: assistant messages with tool_use blocks
                        if src == "claude-code" and e.get("type") == "assistant":
                            msg = e.get("message") or {}
                            for block in msg.get("content") or []:
                                if isinstance(block, dict) and block.get("type") == "tool_use":
                                    name = block.get("name", "?")
                                    tool_counts[name] += 1
                                    tools_by_source["claude-code"][name] += 1

                        # Codex: function_call and custom_tool_call in payload
                        elif src == "codex":
                            etype = e.get("type") or ""
                            if etype == "session_meta":
                                codex_stats["sessions"] += 1
                                p = e.get("payload") or {}
                                if isinstance(p, dict):
                                    model = p.get("model_provider") or ""
                                    if model:
                                        codex_stats["models"][model] += 1
                            elif etype == "response_item":
                                p = e.get("payload") or {}
                                if isinstance(p, dict):
                                    pt = p.get("type") or ""
                                    codex_stats["payload_types"][pt] += 1
                                    if pt in ("function_call", "custom_tool_call"):
                                        name = p.get("name") or "?"
                                        tool_counts[name] += 1
                                        tools_by_source["codex"][name] += 1

                        # OpenCode session logs: service/method tracking
                        elif src == "opencode-session":
                            session = e.get("session") or ""
                            if session:
                                opencode_stats["sessions"].add(session)
                            svc = e.get("service") or ""
                            if svc:
                                opencode_stats["services"][svc] += 1
                            method = e.get("method") or ""
                            if method:
                                opencode_stats["methods"][method] += 1

                        # Cursor audit: tool usage
                        elif src == "cursor-audit":
                            tool = e.get("tool") or ""
                            if tool:
                                cursor_stats["audit_tools"][tool] += 1
                                tool_counts[tool] += 1
                                tools_by_source["cursor"][tool] += 1

                        # Cursor cost: token tracking
                        elif src == "cursor-cost":
                            tokens = e.get("tokens") or 0
                            if isinstance(tokens, (int, float)):
                                cursor_stats["total_tokens"] += int(tokens)
                            tool = e.get("tool") or ""
                            if tool:
                                cursor_stats["cost_tools"][tool] += 1

                        # Cursor diary: aggregated session tool stats
                        elif src == "cursor-diary":
                            cursor_stats["diary_sessions"] += 1
                            tc = e.get("total_tool_calls") or 0
                            if isinstance(tc, (int, float)):
                                cursor_stats["diary_tool_calls"] += int(tc)
                            tool_usage = e.get("tool_usage") or {}
                            if isinstance(tool_usage, dict):
                                for tname, tcount in tool_usage.items():
                                    if isinstance(tcount, (int, float)):
                                        tools_by_source["cursor-diary"][tname] += int(tcount)

            except Exception:
                continue

        proj_list = sorted(
            (
                {**{k: v for k, v in p.items() if k != "sources"},
                 "sources": dict(p["sources"])}
                for p in projects.values()
            ),
            key=lambda p: -p["events"],
        )

        # Serialize source-specific stats
        codex_out = {
            "sessions": codex_stats["sessions"],
            "models": dict(codex_stats["models"]),
            "payload_types": dict(sorted(codex_stats["payload_types"].items(), key=lambda x: -x[1])),
        }
        opencode_out = {
            "sessions": len(opencode_stats["sessions"]),
            "services": dict(sorted(opencode_stats["services"].items(), key=lambda x: -x[1])),
            "methods": dict(sorted(opencode_stats["methods"].items(), key=lambda x: -x[1])),
        }
        cursor_out = {
            "audit_tools": dict(sorted(cursor_stats["audit_tools"].items(), key=lambda x: -x[1])),
            "total_tokens": cursor_stats["total_tokens"],
            "cost_tools": dict(sorted(cursor_stats["cost_tools"].items(), key=lambda x: -x[1])),
            "diary_sessions": cursor_stats["diary_sessions"],
            "diary_tool_calls": cursor_stats["diary_tool_calls"],
        }

        # Merge tools_by_source into serializable dicts
        tbs = {}
        for s, counts in tools_by_source.items():
            tbs[s] = dict(sorted(counts.items(), key=lambda x: -x[1])[:20])

        return {
            "generated_at": now_iso(),
            "files_scanned": files_scanned,
            "total_events": total,
            "sources": dict(sorted(source_counts.items(), key=lambda x: -x[1])),
            "types": dict(sorted(type_counts.items(), key=lambda x: -x[1])),
            "tools": dict(sorted(tool_counts.items(), key=lambda x: -x[1])[:30]),
            "tools_by_source": tbs,
            "projects": proj_list[:50],
            "codex": codex_out,
            "opencode": opencode_out,
            "cursor": cursor_out,
        }


# ---------------------------------------------------------------------------
# Cache layer
# ---------------------------------------------------------------------------

class Cache:
    def __init__(self, sink_root: Path):
        self.sink = SinkData(sink_root)
        self._pipeline_lock = threading.Lock()
        self._pipeline_at: float = 0.0
        self._pipeline: dict | None = None

    def pipeline(self) -> dict:
        with self._pipeline_lock:
            now = time.time()
            if self._pipeline and (now - self._pipeline_at) < 5:
                return self._pipeline
            self._pipeline = fetch_pipeline()
            self._pipeline_at = now
            return self._pipeline

    def sink_data(self) -> dict:
        return self.sink.get()


# ---------------------------------------------------------------------------
# HTML — all server-generated, no user input in any data path
# ---------------------------------------------------------------------------

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Vector Dashboard</title>
<style>
:root{--bg:#0f1117;--surface:#1a1d27;--border:#2a2d3a;--text:#e2e8f0;--muted:#64748b;
--accent:#7c3aed;--green:#22c55e;--red:#ef4444;--yellow:#f59e0b;
--blue:#3b82f6;--orange:#f97316;--pink:#ec4899}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font:13px/1.4 'SF Mono','Fira Code',monospace}
header{padding:8px 16px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px}
header h1{font-size:13px;font-weight:600;color:var(--muted)}
.badge{font-size:10px;padding:1px 6px;border-radius:2px;background:var(--surface);border:1px solid var(--border);color:var(--muted)}
.badge.online{color:var(--green);border-color:var(--green)}
.badge.offline{color:var(--red);border-color:var(--red)}
nav{display:flex;border-bottom:1px solid var(--border);padding:0 16px}
nav button{background:none;border:none;color:var(--muted);cursor:pointer;padding:7px 14px;font:inherit;font-size:12px;border-bottom:1px solid transparent;margin-bottom:-1px;transition:color .1s,border-color .1s}
nav button:hover{color:var(--text)}
nav button.active{color:var(--accent);border-bottom-color:var(--accent)}
.tab{display:none;padding:16px}
.tab.active{display:block}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px;margin-bottom:16px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:2px;padding:10px 12px}
.card h3{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-bottom:4px}
.card .val{font-size:20px;font-weight:700;line-height:1}
.card .sub{font-size:10px;color:var(--muted);margin-top:2px}
table{width:100%;border-collapse:collapse}
th{text-align:left;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);padding:5px 10px;border-bottom:1px solid var(--border)}
td{padding:4px 10px;border-bottom:1px solid var(--border);font-size:12px}
tr:last-child td{border-bottom:none}
tr:hover td{background:#1e2130}
.pill{display:inline-block;font-size:10px;padding:1px 5px;border-radius:2px;background:var(--surface);border:1px solid var(--border)}
.bar-wrap{background:var(--border);border-radius:1px;height:4px;overflow:hidden;margin-top:3px}
.bar{height:100%;border-radius:1px}
.section-title{font-size:10px;font-weight:600;margin-bottom:8px;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}
.section{margin-bottom:20px}
.table-wrap{background:var(--surface);border:1px solid var(--border);border-radius:2px;overflow:hidden}
.flow-layer{margin-bottom:6px}
.flow-label{font-size:9px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin-bottom:4px}
.flow-chips{display:flex;flex-wrap:wrap;gap:4px}
.flow-arrow-row{font-size:11px;color:var(--border);padding:2px 0 2px 4px;margin-bottom:4px}
.comp{background:var(--surface);border:1px solid var(--border);border-radius:2px;padding:5px 8px;min-width:100px}
.comp.comp-active{border-color:var(--accent)}
.comp .name{font-weight:600;font-size:11px}
.comp .metric{font-size:10px;color:var(--muted);margin-top:1px}
.ks.comp-active .name{color:var(--green)}
.kt.comp-active .name{color:var(--yellow)}
.kk.comp-active .name{color:var(--blue)}
.two-col{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.err{background:#2d1b1b;border:1px solid #5a2020;border-radius:2px;padding:12px;color:var(--red)}
.refreshed{font-size:10px;color:var(--muted)}
@media(max-width:700px){.two-col{grid-template-columns:1fr}}
</style>
</head>
<body>
<header>
  <h1>⬡ Vector Dashboard</h1>
  <span id="vec-status" class="badge offline">offline</span>
  <button onclick="forceRefresh()" style="background:none;border:1px solid var(--border);color:var(--muted);cursor:pointer;font:inherit;font-size:11px;padding:2px 8px;border-radius:2px">↺ refresh</button>
  <span id="last-refresh" class="refreshed"></span>
</header>
<nav>
  <button class="active" onclick="showTab('pipeline')">Pipeline</button>
  <button onclick="showTab('projects')">Projects</button>
  <button onclick="showTab('analytics')">Analytics</button>
</nav>
<div id="tab-pipeline" class="tab active"><div id="pipeline-root"></div></div>
<div id="tab-projects" class="tab"><div id="projects-root"></div></div>
<div id="tab-analytics" class="tab"><div id="analytics-root"></div></div>
<script>
const TABS=['pipeline','projects','analytics'];
let activeTab='pipeline';
let sinkData=null;
let sinkMtime=0;

function showTab(name){
  activeTab=name;
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
  document.querySelectorAll('nav button').forEach((b,i)=>{
    b.classList.toggle('active',TABS[i]===name);
  });
  document.getElementById('tab-'+name).classList.add('active');
  refresh();
}

function fmt(n){
  if(n>=1e6)return(n/1e6).toFixed(1)+'M';
  if(n>=1e3)return(n/1e3).toFixed(1)+'K';
  return String(n);
}
function fmtBytes(b){
  if(b>=1073741824)return(b/1073741824).toFixed(1)+' GB';
  if(b>=1048576)return(b/1048576).toFixed(1)+' MB';
  if(b>=1024)return(b/1024).toFixed(1)+' KB';
  return b+' B';
}
function fmtTs(ts){
  if(!ts)return'\u2014';
  try{
    const diff=(Date.now()-new Date(ts).getTime())/1000;
    if(diff<60)return'just now';
    if(diff<3600)return Math.floor(diff/60)+'m ago';
    if(diff<86400)return Math.floor(diff/3600)+'h ago';
    return Math.floor(diff/86400)+'d ago';
  }catch{return ts.slice(0,10);}
}
function srcColor(s){
  if(s.startsWith('claude'))return'#a78bfa';
  if(s.startsWith('opencode'))return'#3b82f6';
  if(s.startsWith('codex'))return'#f97316';
  if(s.startsWith('cursor'))return'#ec4899';
  if(s.startsWith('copilot'))return'#22c55e';
  if(s.startsWith('dotfiles'))return'#f59e0b';
  return'#64748b';
}

// Safe DOM builder — avoids innerHTML with data
function el(tag,attrs,children){
  const e=document.createElement(tag);
  for(const[k,v]of Object.entries(attrs||{})){
    if(k==='style'&&typeof v==='object')Object.assign(e.style,v);
    else if(k==='class')e.className=v;
    else e.setAttribute(k,v);
  }
  for(const c of children||[]){
    if(typeof c==='string')e.appendChild(document.createTextNode(c));
    else if(c)e.appendChild(c);
  }
  return e;
}
function txt(t){return document.createTextNode(String(t));}
function div(cls,children){return el('div',{class:cls},children);}
function span(cls,text){const s=el('span',{class:cls});s.textContent=text;return s;}

function statCard(label,value,sub){
  return div('card',[
    el('h3',{},[txt(label)]),
    el('div',{class:'val'},[txt(value)]),
    sub?el('div',{class:'sub'},[txt(sub)]):null,
  ]);
}

function barRow(label,count,total,color){
  const pct=Math.round(count/total*100);
  const labelEl=el('span',{style:{color:color||'inherit'}},[txt(label||'(unknown)')]);
  const bar=el('div',{class:'bar',style:{width:pct+'%',background:color||'var(--accent)'}});
  const wrap=div('bar-wrap',[bar]);
  const pctEl=el('div',{style:{fontSize:'11px',color:'var(--muted)'}},[txt(pct+'%')]);
  const barCell=el('td',{},[pctEl,wrap]);
  barCell.style.minWidth='140px';
  const tr=el('tr',{},[
    el('td',{},[labelEl]),
    el('td',{},[txt(fmt(count))]),
    barCell,
  ]);
  return tr;
}

function tableWrap(headers,rows){
  const ths=headers.map(h=>el('th',{},[txt(h)]));
  const thead=el('thead',{},[el('tr',{},ths)]);
  const tbody=el('tbody',{},rows);
  const tbl=el('table',{},[thead,tbody]);
  return div('table-wrap',[tbl]);
}

// ---- Pipeline ----
function renderPipeline(data){
  const status=document.getElementById('vec-status');
  const root=document.getElementById('pipeline-root');
  root.textContent='';

  if(data.online){status.textContent='online';status.className='badge online';}
  else{status.textContent='offline';status.className='badge offline';}

  if(!data.online){
    const err=div('err',[txt('Vector API unreachable: '+(data.error||'connection refused'))]);
    const hint=el('small',{style:{color:'var(--muted)'}},[txt('Start Vector or check port 9598')]);
    err.appendChild(el('br',{}));
    err.appendChild(hint);
    root.appendChild(err);
    return;
  }

  const comps=data.components||[];
  const sources=comps.filter(c=>c.kind==='source');
  const transforms=comps.filter(c=>c.kind==='transform');
  const sinks=comps.filter(c=>c.kind==='sink');

  // Summary
  const grid=div('grid',[
    statCard('Total Events',fmt(data.total_events||0),'from sources'),
    statCard('Bytes Received',fmtBytes(data.total_bytes||0),'across all sources'),
    statCard('Sources',String(sources.length)),
    statCard('Transforms',String(transforms.length)),
    statCard('Sinks',String(sinks.length)),
  ]);
  root.appendChild(grid);

  // Flow — layered table: sources row → transforms row → sinks row
  const flowSec=div('section',[el('div',{class:'section-title'},[txt('Data Flow')])]);

  function makeLayer(arr,cls,label){
    const layer=div('flow-layer');
    const lbl=el('div',{class:'flow-label'},[txt(label)]);
    const chips=div('flow-chips');
    arr.forEach(c=>{
      const active=c.events>0;
      const chip=div('comp '+cls+(active?' comp-active':''),[
        el('div',{class:'name'},[txt(c.id)]),
        el('div',{class:'metric'},[txt(active?fmt(c.events)+' ev':'synced')]),
        c.bytes?el('div',{class:'metric'},[txt(fmtBytes(c.bytes))]):null,
      ]);
      chips.appendChild(chip);
    });
    layer.appendChild(lbl);
    layer.appendChild(chips);
    return layer;
  }

  if(sources.length) flowSec.appendChild(makeLayer(sources,'ks','Sources'));
  if(transforms.length){
    flowSec.appendChild(el('div',{class:'flow-arrow-row'},[txt('\u2193')]));
    flowSec.appendChild(makeLayer(transforms,'kt','Transforms'));
  }
  if(sinks.length){
    flowSec.appendChild(el('div',{class:'flow-arrow-row'},[txt('\u2193')]));
    flowSec.appendChild(makeLayer(sinks,'kk','Sinks'));
  }
  root.appendChild(flowSec);

  // Component table — note these are since-last-restart counters
  const rows=comps.map(c=>el('tr',{},[
    el('td',{},[txt(c.id)]),
    el('td',{},[span('pill',c.kind)]),
    el('td',{},[txt(fmt(c.events))]),
    el('td',{},[txt(c.bytes?fmtBytes(c.bytes):'\u2014')]),
  ]));
  const note=el('div',{style:{fontSize:'10px',color:'var(--muted)',marginBottom:'6px'}},[
    txt('Event counts reset on each Vector restart. 0 = fully synced (no new data since last start).')
  ]);
  const sec=div('section',[el('div',{class:'section-title'},[txt('Components (since last restart)')]),note,tableWrap(['ID','Kind','Events','Bytes'],rows)]);
  root.appendChild(sec);

  // Sink all-time breakdown from the sink file
  fetch('/api/sink').then(r=>r.json()).then(sink=>{
    const srcs=sink.sources||{};
    const total=Object.values(srcs).reduce((a,b)=>a+b,0)||1;
    const sinkRows=Object.entries(srcs).map(([s,n])=>barRow(s,n,total,srcColor(s)));
    const sinkSec=div('section',[
      el('div',{class:'section-title'},[txt('Sink — all-time by source')]),
      tableWrap(['Source','Events','Share'],sinkRows),
    ]);
    root.appendChild(sinkSec);
  }).catch(()=>{});
}

// ---- Projects ----
function renderProjects(data){
  const root=document.getElementById('projects-root');
  root.textContent='';
  const projects=data.projects||[];
  const maxEv=projects[0]?.events||1;

  root.appendChild(div('grid',[
    statCard('Total Events',fmt(data.total_events||0)),
    statCard('Files Scanned',String(data.files_scanned||0)),
    statCard('Active Projects',String(projects.length)),
  ]));

  const rows=projects.map(p=>{
    const pct=Math.round(p.events/maxEv*100);
    const bar=el('div',{class:'bar',style:{width:pct+'%',background:'var(--accent)'}});
    const barWrap=div('bar-wrap',[bar]);
    const evCell=el('td',{},[el('div',{},[txt(fmt(p.events))]),barWrap]);

    const cwdCell=el('td',{title:p.cwd});
    cwdCell.style.cssText='max-width:280px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
    cwdCell.textContent=p.cwd;

    const brCell=el('td',{style:{color:'var(--muted)'}},[txt(p.branch||'\u2014')]);
    const tsCell=el('td',{},[txt(fmtTs(p.last_ts))]);

    const srcCell=el('td',{style:{fontSize:'11px'}});
    Object.entries(p.sources||{}).sort((a,b)=>b[1]-a[1]).slice(0,3).forEach(([s])=>{
      const sp=document.createElement('span');
      sp.style.color=srcColor(s);
      sp.style.marginRight='6px';
      sp.textContent=s;
      srcCell.appendChild(sp);
    });

    return el('tr',{},[cwdCell,evCell,brCell,tsCell,srcCell]);
  });

  const sec=div('section',[
    el('div',{class:'section-title'},[txt('Projects by Activity')]),
    tableWrap(['Directory','Events','Branch','Last Active','Sources'],rows),
  ]);
  root.appendChild(sec);
}

// ---- Analytics ----
function renderAnalytics(data){
  const root=document.getElementById('analytics-root');
  root.textContent='';
  const sources=data.sources||{};
  const types=data.types||{};
  const tools=data.tools||{};
  const tbs=data.tools_by_source||{};
  const codex=data.codex||{};
  const opencode=data.opencode||{};
  const cursor=data.cursor||{};
  const toolTotal=Object.values(tools).reduce((a,b)=>a+b,0);
  const srcTotal=Object.values(sources).reduce((a,b)=>a+b,0)||1;
  const typeTotal=Object.values(types).reduce((a,b)=>a+b,0)||1;

  root.appendChild(div('grid',[
    statCard('Total Events',fmt(data.total_events||0)),
    statCard('Sources',String(Object.keys(sources).length)),
    statCard('Tool Calls',fmt(toolTotal),'all sources'),
    statCard('Codex Sessions',String(codex.sessions||0)),
    statCard('OpenCode Sessions',String(opencode.sessions||0)),
    statCard('Cursor Tokens',fmt(cursor.total_tokens||0)),
  ]));

  const twoCol=div('two-col');

  // Sources
  const srcRows=Object.entries(sources).map(([s,n])=>barRow(s,n,srcTotal,srcColor(s)));
  twoCol.appendChild(div('section',[
    el('div',{class:'section-title'},[txt('Events by Source')]),
    tableWrap(['Source','Events','Share'],srcRows),
  ]));

  // Types
  const typeRows=Object.entries(types).slice(0,12).map(([t,n])=>barRow(t,n,typeTotal,'var(--blue)'));
  twoCol.appendChild(div('section',[
    el('div',{class:'section-title'},[txt('Message Types')]),
    tableWrap(['Type','Count','Share'],typeRows),
  ]));

  root.appendChild(twoCol);

  // Combined top tools
  if(Object.keys(tools).length){
    const toolRows=Object.entries(tools).slice(0,20).map(([t,n])=>{
      // Find which source(s) this tool belongs to
      let color='var(--muted)';
      for(const[s,tm]of Object.entries(tbs)){
        if(tm[t]){color=srcColor(s);break;}
      }
      return barRow(t,n,toolTotal||1,color);
    });
    root.appendChild(div('section',[
      el('div',{class:'section-title'},[txt('Top Tools (All Sources)')]),
      tableWrap(['Tool','Calls','Share'],toolRows),
    ]));
  }

  // Per-source tool breakdowns
  const tbsEntries=Object.entries(tbs).filter(([,v])=>Object.keys(v).length>0);
  if(tbsEntries.length>1){
    const perSrcCol=div('two-col');
    for(const[src,tm]of tbsEntries){
      const total=Object.values(tm).reduce((a,b)=>a+b,0)||1;
      const rows=Object.entries(tm).slice(0,12).map(([t,n])=>barRow(t,n,total,srcColor(src)));
      perSrcCol.appendChild(div('section',[
        el('div',{class:'section-title'},[txt('Tools \u2014 '+src)]),
        tableWrap(['Tool','Calls','Share'],rows),
      ]));
    }
    root.appendChild(perSrcCol);
  }

  // --- Source-specific sections ---
  const detailCol=div('two-col');
  let hasDetail=false;

  // Codex details
  const codexPt=codex.payload_types||{};
  if(Object.keys(codexPt).length){
    hasDetail=true;
    const ptTotal=Object.values(codexPt).reduce((a,b)=>a+b,0)||1;
    const ptRows=Object.entries(codexPt).map(([t,n])=>barRow(t,n,ptTotal,'var(--orange)'));
    const models=codex.models||{};
    const modelInfo=Object.entries(models).map(([m,n])=>m+' ('+n+')').join(', ')||'\u2014';
    const header=el('div',{style:{fontSize:'11px',color:'var(--muted)',marginBottom:'6px'}},[
      txt('Sessions: '+codex.sessions+' \u00b7 Models: '+modelInfo)
    ]);
    detailCol.appendChild(div('section',[
      el('div',{class:'section-title'},[txt('Codex \u2014 Payload Types')]),
      header,
      tableWrap(['Type','Count','Share'],ptRows),
    ]));
  }

  // OpenCode details
  const ocSvc=opencode.services||{};
  if(Object.keys(ocSvc).length){
    hasDetail=true;
    const svcTotal=Object.values(ocSvc).reduce((a,b)=>a+b,0)||1;
    const svcRows=Object.entries(ocSvc).slice(0,10).map(([s,n])=>barRow(s,n,svcTotal,'var(--blue)'));
    const methods=opencode.methods||{};
    const methTotal=Object.values(methods).reduce((a,b)=>a+b,0)||1;
    const methRows=Object.entries(methods).slice(0,8).map(([m,n])=>barRow(m,n,methTotal,'#60a5fa'));
    const header=el('div',{style:{fontSize:'11px',color:'var(--muted)',marginBottom:'6px'}},[
      txt('Sessions: '+opencode.sessions)
    ]);
    detailCol.appendChild(div('section',[
      el('div',{class:'section-title'},[txt('OpenCode \u2014 Services & Methods')]),
      header,
      tableWrap(['Service','Events','Share'],svcRows),
      el('div',{style:{height:'10px'}}),
      tableWrap(['Method','Events','Share'],methRows),
    ]));
  }

  // Cursor details
  const cursorAudit=cursor.audit_tools||{};
  const cursorCost=cursor.cost_tools||{};
  if(Object.keys(cursorAudit).length||cursor.total_tokens||cursor.diary_sessions){
    hasDetail=true;
    const sec=div('section',[el('div',{class:'section-title'},[txt('Cursor \u2014 Usage')])]);
    const info=[];
    if(cursor.total_tokens)info.push('Tokens: '+fmt(cursor.total_tokens));
    if(cursor.diary_sessions)info.push('Diary sessions: '+cursor.diary_sessions+' ('+fmt(cursor.diary_tool_calls||0)+' tool calls)');
    if(info.length){
      sec.appendChild(el('div',{style:{fontSize:'11px',color:'var(--muted)',marginBottom:'6px'}},[txt(info.join(' \u00b7 '))]));
    }
    if(Object.keys(cursorAudit).length){
      const auditTotal=Object.values(cursorAudit).reduce((a,b)=>a+b,0)||1;
      const auditRows=Object.entries(cursorAudit).slice(0,10).map(([t,n])=>barRow(t,n,auditTotal,'var(--pink)'));
      sec.appendChild(tableWrap(['Audit Tool','Calls','Share'],auditRows));
    }
    if(Object.keys(cursorCost).length){
      sec.appendChild(el('div',{style:{height:'10px'}}));
      const costTotal=Object.values(cursorCost).reduce((a,b)=>a+b,0)||1;
      const costRows=Object.entries(cursorCost).slice(0,10).map(([t,n])=>barRow(t,n,costTotal,'#f472b6'));
      sec.appendChild(tableWrap(['Cost Tool','Events','Share'],costRows));
    }
    detailCol.appendChild(sec);
  }

  if(hasDetail)root.appendChild(detailCol);
}

// ---- Fetch & refresh ----
async function refresh(){
  try{
    if(activeTab==='pipeline'){
      const r=await fetch('/api/pipeline');
      renderPipeline(await r.json());
    }else{
      if(!sinkData){
        const r=await fetch('/api/sink');
        const d=await r.json();
        sinkData=d;
      }
      if(activeTab==='projects')renderProjects(sinkData);
      else renderAnalytics(sinkData);
    }
    document.getElementById('last-refresh').textContent='refreshed '+new Date().toLocaleTimeString();
  }catch(e){console.error(e);}
}

function forceRefresh(){
  sinkData=null;
  sinkMtime=0;
  refresh();
}

// Poll every 10s: always check sink mtime (not just on non-pipeline tabs)
setInterval(()=>{
  fetch('/api/sink/mtime').then(r=>r.json()).then(d=>{
    if(d.mtime!==sinkMtime){sinkMtime=d.mtime;sinkData=null;}
  }).catch(()=>{});
  refresh();
},10000);

refresh();
</script>
</body>
</html>"""


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    cache: "Cache"

    def log_message(self, fmt, *args):
        pass

    def send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            body = HTML.encode()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == "/api/pipeline":
            self.send_json(self.cache.pipeline())
        elif path == "/api/sink":
            self.send_json(self.cache.sink_data())
        elif path == "/api/sink/mtime":
            self.send_json({"mtime": self.cache.sink.current_mtime()})
        else:
            self.send_response(404)
            self.end_headers()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Vector dashboard")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--sink", type=Path, default=DEFAULT_SINK,
                        help="Path to Vector sink directory (default: ~/logs/ai/vector)")
    args = parser.parse_args()

    cache = Cache(args.sink)

    class BoundHandler(Handler):
        pass
    BoundHandler.cache = cache

    server = ThreadingHTTPServer(("127.0.0.1", args.port), BoundHandler)
    url = f"http://localhost:{args.port}"
    print(f"Vector dashboard -> {url}")
    print(f"Sink: {args.sink}")
    print("Ctrl-C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
