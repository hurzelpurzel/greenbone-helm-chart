# AGENTS.md

Helm chart packaging the OpenVAS / Greenbone Community Edition 22.4 stack for Kubernetes. The upstream source of truth is `doc/docker-compose-22.4.yml` (the official Greenbone compose file); the chart was generated from it with `kompose convert -f docker-compose-22.4.yml`, then hand-refactored.

## Layout

- `greenbone-ce/` — the only Helm chart (`Chart.yaml`, `values.yaml`, `templates/`).
- `doc/docker-compose-22.4.yml` — upstream reference; consult it when a container's config looks wrong.

## Key facts / gotchas

- **Dead templates:** Helm ignores files starting with `_` (they only render via `include`/`tpl`). The `_*-pod.yaml` and `_*-data-deployment.yaml` files are leftover kompose output that is NOT deployed. Do not edit them expecting changes to apply — either delete them or wire them into the live `*deployment.yaml`/`*pod.yaml` files. Live output is only: `pvcs.yaml`, the three `*service.yaml`, `mqtt-broker-pod.yaml`, and `gvm-tools|gvmd|notus-scanner|openvas-deployment.yaml`.
- **Data seeding moved to initContainers.** In the upstream compose, data jobs (`scap-data`, `cert-bund-data`, `dfn-cert-data`, `data-objects`, `report-formats`, `gpg-data`, `vulnerability-tests`, `notus-data`) run as `depends_on: service_completed_successfully` jobs. In this chart they were converted into initContainers of `gvmd-deployment.yaml` and `openvas-deployment.yaml`. The separate `_*-data-deployment.yaml` files are duplicates from that conversion and are dead.
- **All PVCs are `ReadWriteMany`**, 100Mi, with fixed names (`cert-data-vol`, `data-objects-vol`, `gpg-data-vol`, `gvmd-data-vol`, `gvmd-socket-vol`, `notus-data-vol`, `ospd-openvas-socket-vol`, `psql-data-vol`, `psql-socket-vol`, `redis-socket-vol`, `scap-data-vol`, `vt-data-vol`). The chart hard-codes claimName references; there is no storageClass, size, or RWO config in `values.yaml`.
- **Service discovery uses raw names**, not `.Release.Name`-prefixed FQDNs: e.g. `mqtt-broker.{{.Release.Namespace}}.svc.cluster.local` in `notus-scanner-deployment.yaml` (hard-coded to the literal namespace — a bug if you override it) and `$(MQTT_BROKER_SERVICE_HOST)` in `openvas-deployment.yaml`. `_helpers.tpl` names exist but are mostly unused by these services.
- **Composite gvmd deploy** (`gvmd-deployment.yaml`): name is literally `gmvd` (typo, deployed as-is), and it multipacks gsa + pg-gvm + gvmd as three containers in one pod. Its comment-missing mount uses `mountPath: /va/lib/postgresql` (missing an `r`) — a latent misconfiguration. `strategy: Recreate` everywhere.
- **`gvmd` pod and `openvas` pod selectors are inconsistent**: some Deployments use `matchLabels: app: <name>` with pod labels set separately from the `greenbone-ce.selectorLabels` helper, so label changes in `_helpers.tpl` won't propagate to those selectors.

## Verification

- Render the chart: `helm template <release> greenbone-ce`, or lint with `helm lint greenbone-ce`.
- No tests, CI, formatter, or linter config exist in this repo.
