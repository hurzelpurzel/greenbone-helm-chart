#!/usr/bin/env bash

SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

usage() {
    cat <<EOM

Applies hand-crafted additions to the kompose-generated chart so they survive
regeneration:

  1. Writes values.yaml exposing imagePullSecrets for the private
     registry.community.greenbone.net registry.
  2. Injects the {{- with .Values.imagePullSecrets }} block into every
     Deployment pod spec (idempotent).
  3. Ensures the README documents how to create and reference the image pull
     secret (idempotent).

usage: ${SCRIPT_NAME} --chart-dir <path>

options:
    --chart-dir <path>   Root directory of the generated chart (required)
    -h | --help          Show this help message

dependencies: awk, grep, sed, cat

examples:
    ${SCRIPT_NAME} --chart-dir kompose-generated

EOM
    exit 1
}

write_values_yaml() {
    local chart_dir="$1"
    cat > "${chart_dir}/values.yaml" <<'EOF'
# -- Existing images are pulled from registry.community.greenbone.net which
# requires authentication.  Create a Kubernetes docker-registry secret and
# reference its name here so that every pod can pull images from the private
# registry.
#
# Example:
#   kubectl create secret docker-registry greenbone-registry \
#     --docker-server=registry.community.greenbone.net \
#     --docker-username=<your-username> \
#     --docker-password=<your-password> \
#     --docker-email=<your-email>
#
# helm install greenbone-ce . --set imagePullSecrets[0].name=greenbone-registry

# -- Array of image-pull secrets applied to every Deployment pod spec.
# Each entry must be a map with a `name` key whose value matches an existing
# kubernetes.io/dockerconfigjson secret.
imagePullSecrets: []
  # - name: greenbone-registry
EOF
    echo "Wrote: ${chart_dir}/values.yaml"
}

inject_image_pull_secrets() {
    local chart_dir="$1"
    local template_dir="${chart_dir}/templates"
    local block
    local file tmpfile found

    block=$'      {{- with .Values.imagePullSecrets }}\n      imagePullSecrets:\n        {{- toYaml . | nindent 8 }}\n      {{- end }}'

    found=false
    for file in "${template_dir}"/*-deployment.yaml; do
        if [ -e "$file" ]; then
            found=true
            break
        fi
    done
    if [ "$found" != "true" ]; then
        echo "Error: No *-deployment.yaml found in ${template_dir}" >&2
        return 1
    fi

    for file in "${template_dir}"/*-deployment.yaml; do
        if grep -q 'imagePullSecrets' "$file"; then
            echo "Skip (already annotated): ${file}"
            continue
        fi
        tmpfile=$(mktemp)
        awk -v block="$block" '
            /^    spec:$/ && !done {
                print
                print block
                done = 1
                next
            }
            { print }
        ' "$file" > "$tmpfile"
        if [ "$?" -ne 0 ]; then
            rm -f "$tmpfile"
            echo "Error: awk failed on ${file}" >&2
            return 1
        fi
        if ! grep -q 'imagePullSecrets' "$tmpfile"; then
            rm -f "$tmpfile"
            echo "Error: Pod spec not found in ${file}" >&2
            return 1
        fi
        mv "$tmpfile" "$file"
        echo "Injected imagePullSecrets into: ${file}"
    done
}

ensure_readme_section() {
    local chart_dir="$1"
    local readme="${chart_dir}/README.md"
    local marker="## Image Pull Secret"

    if [ ! -f "$readme" ]; then
        echo "Error: ${readme} not found" >&2
        return 1
    fi
    if grep -qF "$marker" "$readme"; then
        echo "Skip (section already present): ${readme}"
        return 0
    fi
    cat >> "$readme" <<'EOF'

## Image Pull Secret

All images are pulled from the private registry
`registry.community.greenbone.net`, so Kubernetes needs credentials to pull
them. Create them through the Greenbone Community Portal:

1. Go to https://community.greenbone.net
2. Select **Register** or **Sign up**.
3. Confirm your email address.
4. Use those credentials to authenticate to `registry.community.greenbone.net`.

Create a `kubernetes.io/dockerconfigjson` secret in the cluster with the same
Server, Username, Password and Email credentials:

```bash
kubectl create secret docker-registry greenbone-registry \
  --docker-server=registry.community.greenbone.net \
  --docker-username=<your-username> \
  --docker-password=<your-password> \
  --docker-email=<your-email> \
  --namespace=<namespace>
```

Reference the secret by name so every Deployment can pull images:

```bash
helm install greenbone-ce . \
  --namespace=<namespace> \
  --set imagePullSecrets[0].name=greenbone-registry
```

Alternatively, set it in a custom `values.yaml`:

```yaml
imagePullSecrets:
  - name: greenbone-registry
```
EOF
    echo "Added Image Pull Secret section to: ${readme}"
}

main() {
    local chart_dir=""

    while [ "$1" != "" ]; do
        case $1 in
        --chart-dir)
            shift
            chart_dir="$1"
            ;;
        -h | --help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage
            ;;
        esac
        shift
    done

    if [ -z "$chart_dir" ]; then
        echo "Error: --chart-dir is required" >&2
        usage
    fi

    if [ ! -d "$chart_dir" ]; then
        echo "Error: Chart directory does not exist: ${chart_dir}" >&2
        exit 1
    fi

    write_values_yaml "$chart_dir"
    inject_image_pull_secrets "$chart_dir"
    if [ "$?" -ne 0 ]; then
        echo "Error: image pull secret injection failed" >&2
        exit 1
    fi
    ensure_readme_section "$chart_dir"
    if [ "$?" -ne 0 ]; then
        echo "Error: README update failed" >&2
        exit 1
    fi

    echo "Postprocessing complete: ${chart_dir}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
