# qwc-docker Helm Umbrella Chart

This chart deploys the QWC Docker stack from `docker-compose-example.yml` into Kubernetes using Helm.

## What this chart maps from docker-compose

- Each docker-compose service is represented as a Helm subchart (for example `qwc-auth-service`, `qwc-map-viewer`, `qwc-api-gateway`).
- Service images and tags match the compose example defaults in `values.yaml`.
- Bind mounts from compose are translated to fixed service mount paths backed by one shared PVC.
- The nginx API gateway config is shipped as a ConfigMap (`qwc-api-gateway.configMap.data.nginx.conf`).

## Prerequisites

- A Kubernetes cluster with Helm 3.
- A namespace for QWC (examples below use `qwc`).
- A ReadWriteMany storage class, or an existing shared PVC with all required files.
- The files from `qwc-docker/volumes` and `qwc-docker/pg_service.conf` copied into shared storage.

## Storage layout required by the chart

The chart expects one shared PVC mounted by all services. The default subPaths in `values.yaml` assume this structure inside the volume:

```text
/
|- pg_service.conf
`- vector/qwc-storage/
   |- attachments/
   |- config/
   |- config-in/
   |- db/
   |- legends/
   |- print-layouts/
   |- qgs-resources/
   |- qwc2/
   |- reports/
   `- solr/
      |- configsets/gdi/
      `- data/
```

If your storage layout differs, override each service `sharedStorage.subPaths.<key>` in your custom values file.

The expected mount paths are defined by each service chart and are not configurable.
For shared PVC mounts, the intended override point is only `subPath`.
If you need additional files or mounts, use `extraVolumes` and `extraVolumeMounts`.

## Shared storage contract

- Fixed by chart: `mountPath`, `readOnly`, volume name (`shared-storage`).
- Overridable by environment: `sharedStorage.subPaths.<key>` values.
- Extension point: `extraVolumes` and `extraVolumeMounts` for additional custom mounts.

Example override:

```yaml
qwc-config-service:
  sharedStorage:
    subPaths:
      configIn: custom/config-in
      configOut: custom/config
```

Migration from the old format:

```yaml
# old
qwc-config-service:
  sharedStorage:
    mounts:
      - mountPath: /srv/qwc_service/config-in
        subPath: vector/qwc-storage/config-in

# new
qwc-config-service:
  sharedStorage:
    subPaths:
      configIn: vector/qwc-storage/config-in
```

## Workload kinds

- `qwc-config-db-migrate` is always deployed as a `Job`.
- `qwc-postgis` and `qwc-solr` are always deployed as `StatefulSet`.
- All other QWC services are always deployed as `Deployment`.

## 1) Create namespace

```bash
kubectl create namespace qwc
```

## 2) Prepare values file

Create `values-qwc.yaml`:

```yaml
global:
  cloudProvider:
    dockerRegistryUrl: ""          # optional, e.g. my-registry.example.com
    imagePullSecretName: ""        # optional
  sharedStorage:
    existingClaim: qwc-shared       # pre-created RWX PVC
    create: false

qwc-config-service:
  env:
    - name: INPUT_CONFIG_PATH
      value: /srv/qwc_service/config-in
    - name: OUTPUT_CONFIG_PATH
      value: /srv/qwc_service/config-out
    - name: GENERATE_DYNAMIC_KVRELS
      value: "1"
    - name: JWT_SECRET_KEY
      value: "replace-with-strong-random-secret"
    - name: JWT_COOKIE_CSRF_PROTECT
      value: "True"
    - name: JWT_COOKIE_SAMESITE
      value: "Strict"

qwc-admin-gui:
  env:
    - name: JWT_SECRET_KEY
      value: "replace-with-strong-random-secret"
    - name: JWT_COOKIE_CSRF_PROTECT
      value: "False"
    - name: JWT_COOKIE_SAMESITE
      value: "Strict"
    - name: GROUP_REGISTRATION_ENABLED
      value: "True"
    - name: DEFAULT_LOCALE
      value: en

qwc-auth-service:
  env:
    - name: JWT_SECRET_KEY
      value: "replace-with-strong-random-secret"
    - name: JWT_COOKIE_CSRF_PROTECT
      value: "True"
    - name: JWT_COOKIE_SAMESITE
      value: "Strict"
    - name: SERVICE_MOUNTPOINT
      value: /auth

qwc-data-service:
  env:
    - name: JWT_SECRET_KEY
      value: "replace-with-strong-random-secret"
    - name: JWT_COOKIE_CSRF_PROTECT
      value: "True"
    - name: JWT_COOKIE_SAMESITE
      value: "Strict"
    - name: SERVICE_MOUNTPOINT
      value: /api/v1/data
    - name: ATTACHMENTS_BASE_DIR
      value: /attachments

# Repeat JWT_* env vars for the other QWC services if needed.
```

Notes:

- In docker-compose, JWT env vars are inherited through `x-qwc-service-variables`; in Helm shared JWT env defaults are in `global.commonEnv`, and per-service additions stay under each service `env`.
- `qwc-postgis.env.POSTGRES_PASSWORD` is empty by default in this chart; set it explicitly for non-demo deployments.

## 3) Install the chart

From the `qwc-docker/helm` directory:

```bash
helm dependency build
helm upgrade --install qwc . -n qwc -f values-qwc.yaml
```

## 4) Expose the API gateway

Option A (Ingress):

```yaml
qwc-api-gateway:
  ingress:
    enabled: true
    className: nginx
    host: qwc.example.com
    path: /
    pathType: Prefix
```

Option B (temporary port-forward):

```bash
kubectl -n qwc port-forward svc/qwc-api-gateway 8088:80
```

Then open `http://localhost:8088`.

Option C (OpenShift Route):

```yaml
qwc-api-gateway:
  route:
    enabled: true
    host: qwc.apps.example.com
    path: /
    wildcardPolicy: None
    tls:
      enabled: true
      termination: edge
      insecureEdgeTerminationPolicy: Redirect
```

## 5) Verify deployment

```bash
kubectl -n qwc get pods
kubectl -n qwc get svc
kubectl -n qwc logs deploy/qwc-api-gateway
```

## Common customizations

- OpenShift compatibility (non-root nginx):
  - The default chart uses `nginxinc/nginx-unprivileged` and listens on container port `8080`.
  - Kubernetes Service still exposes port `80` and forwards to `targetPort: 8080`.

- Disable a service:

```yaml
qwc-auth-service:
  enabled: false
```

- Use a private registry for all images:

```yaml
global:
  cloudProvider:
    dockerRegistryUrl: my-registry.example.com
    imagePullSecretName: regcred
```

- Let Helm create the shared PVC instead of using an existing one:

```yaml
global:
  sharedStorage:
    existingClaim: ""
    create: true
    size: 50Gi
    storageClassName: nfs-rwx
```

- Trust additional public CAs for external HTTPS calls from `qwc-qgis-server`:

Create a ConfigMap with one or more certificate files:

```bash
kubectl -n qwc create configmap qgis-extra-cas \
  --from-file=corp-root-ca.crt \
  --from-file=corp-intermediate-ca.crt
```

Then configure `qwc-qgis-server`:

```yaml
qwc-qgis-server:
  env:
    - name: PORT
      value: "8080"
    - name: SSL_CERT_DIR
      value: /etc/ssl/certs:/usr/local/share/ca-certificates/custom
  extraVolumes:
    - name: external-ca-certs
      configMap:
        name: qgis-extra-cas
  extraVolumeMounts:
    - name: external-ca-certs
      mountPath: /usr/local/share/ca-certificates/custom
      readOnly: true
```

This adds extra certs without replacing the container's default certificates.

- Mount `qgis-auth.db` and generate `qgis-auth.txt` from `masterKey` for `qwc-qgis-server`:

Place `qgis-auth.db` in the subchart files directory:

```text
qwc-docker/helm/charts/qwc-qgis-server/files/qgis-auth/qgis-auth.db
```

Then enable auth files in values:

```yaml
qwc-qgis-server:
  qgisAuthFiles:
    enabled: true
    secretName: qgis-auth-files
    dbKey: qgis-auth.db
    txtKey: qgis-auth.txt
    dbFilePath: files/qgis-auth/qgis-auth.db
    masterKey: "replace-with-master-key"
```

The chart creates a Secret from the chart file and mounts it as:
- `/var/lib/qgis/qgis-auth.db`
- `/var/lib/qgis/qgis-auth.txt`

Note: `.Files.Get*` can only read files packaged inside the chart.

## Relevant files

- Compose reference: `qwc-docker/docker-compose-example.yml`
- Chart values: `qwc-docker/helm/values.yaml`
- Helm chart definition: `qwc-docker/helm/Chart.yaml`
