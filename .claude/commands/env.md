---
name: env
description: Debug secrets and environment issues — diagnoses op run conflicts, direnv chains, 1Password access, and Tailscale connectivity.
allowed-tools: Agent
argument-hint: '[issue description or leave blank for full diagnostic]'
author: Joseph OBrien
tag: commands
---

# Env

Use the @envoy agent to diagnose the environment issue. Description: $ARGUMENTS. If no arguments provided, run the full diagnostic chain: direnv → source_up → op connectivity → conflicting vars.
