# Example conformance runs

Captured `llmd-infra-check` output from real clusters, for reference when
reading your own results. Cluster/project identifiers are sanitized; all other
figures are verbatim.

## Reading the output

* Each selected check prints `[ PASS ]` / `[ FAIL ]` / `[ SKIP ]` plus a
  one-line evidence summary (`ok: ...`) stating what was actually observed
  (server version, node counts, allocatable GPUs, published devices, measured
  bandwidth). Keep this output with your qualification evidence (see
  GOVERNANCE.md, "Quality bar"): the evidence lines are what make a recorded
  run auditable later.
* `not applicable` counts checks whose dimension constraints do not match the
  requested profile; they are hidden unless `-v` is given.
* `[ DEFER]` marks micro-tests that were selected but not run because
  `--microtests` was absent.
* Exit code is 0 only when no selected check failed.

## Included examples

* [gke-gpu-standalone-pass.txt](gke-gpu-standalone-pass.txt) - fully passing
  static run against a live GKE cluster (86 GB200 nodes), dimension space
  `infra_provider=gke accelerator=gpu rdma=none dra=none router_mode=standalone`.
  Captured 2026-08-10 with the suite at its initial revision.
* [gke-a4x-multinet-standalone-pass.txt](gke-a4x-multinet-standalone-pass.txt) -
  fully passing run INCLUDING the two-node NCCL fabric micro-test
  (`--microtests`) on the same A4X cluster, dimension space
  `infra_provider=gke accelerator=gpu rdma=roce dra=none router_mode=standalone`.
  Shows the shape-guard behavior (the A3U/A4 multinet variant SKIPs on GB200)
  and a measured 189.3 GB/s peak bus bandwidth. Captured 2026-08-11.
* [gke-a4x-nccl-all-gather-detail.txt](gke-a4x-nccl-all-gather-detail.txt) -
  the full nccl-tests sweep (1K-8G) behind that micro-test's evidence line:
  per-size algbw/busbw columns, `#wrong 0` throughout, peak 189.33 GB/s
  (~95% of the 4x400G per-node line rate).

A failing check looks like this (same cluster, `gke-optimized-baseline`
profile, before Gateway API enablement): the indented output states the
observed condition and the remediation.

```
[ FAIL ] gke.gateway-classes - GKE-managed GatewayClasses used by llm-d recipes are present and accepted
         error: neither gke-l7-rilb nor gke-l7-regional-external-managed is present+accepted
         (enable the Gateway API: gcloud container clusters update --gateway-api=standard)
...
summary: 7 passed, 2 failed, 0 skipped, 0 deferred, 8 not applicable
failed checks: gateway.controller-accepted gke.gateway-classes
result: cluster is NOT ready for the requested llm-d dimension profile
```

## Contributing an example

When you qualify a provider profile, add a sanitized capture here named
`<profile>-pass.txt` (or `<dimension-summary>-pass.txt` for ad-hoc dimension
spaces) and reference it from your provider README's qualification table.
Sanitize project/cluster/context identifiers; keep versions, counts, and
bandwidth figures intact, since those carry the evidentiary value.
