{{/*
Expand the name of the chart.
*/}}
{{- define "agent-api-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agent-api-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "agent-api-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agent-api-chart.labels" -}}
helm.sh/chart: {{ include "agent-api-chart.chart" . }}
{{ include "agent-api-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agent-api-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent-api-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "agent-api-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "agent-api-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Returns the PostgreSQL service endpoint
*/}}
{{- define "agent-api-chart.postgresql.fullname" -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end }}

{{/*
Returns the PostgreSQL service hostname
*/}}
{{- define "agent-api-chart.postgresql.endpoint" -}}
{{- printf "%s.%s.svc.cluster.local" (include "agent-api-chart.postgresql.fullname" .) .Release.Namespace -}}
{{- end }}

{{/*
Returns the Secret holding DATABASE_URL and the PostgreSQL password.
External Secrets populates both keys. When running with postgresql.enabled=false,
point postgresql.auth.existingSecret at your own Secret carrying a DATABASE_URL key.
*/}}
{{- define "agent-api-chart.dbSecretName" -}}
{{- $name := dig "auth" "existingSecret" "" (.Values.postgresql | default dict) -}}
{{- required "postgresql.auth.existingSecret must be set: the app reads DATABASE_URL from this Secret" $name -}}
{{- end }}

{{/*
Returns the Secret holding REDIS_URL and the Redis password.
External Secrets populates both keys. When running with redis.enabled=false,
this is not rendered at all.
*/}}
{{- define "agent-api-chart.redisSecretName" -}}
{{- $name := dig "auth" "existingSecret" "" (.Values.redis | default dict) -}}
{{- required "redis.auth.existingSecret must be set: the app reads REDIS_URL from this Secret" $name -}}
{{- end }}

{{/*
Returns the Redis service fullname
*/}}
{{- define "agent-api-chart.redis.fullname" -}}
{{- printf "%s-redis-master" .Release.Name -}}
{{- end }}

{{/*
Returns the Redis service hostname
*/}}
{{- define "agent-api-chart.redis.endpoint" -}}
{{- printf "%s.%s.svc.cluster.local" (include "agent-api-chart.redis.fullname" .) .Release.Namespace -}}
{{- end }}

{{/*
Full image reference for the app container.
global.imageRegistry (host+org prefix, e.g. "myregistry.example.com/mirror")
overrides image.registry; both fall back to ghcr.io/bouc-io.
*/}}
{{- define "agent-api-chart.image" -}}
{{- $global := .Values.global | default dict -}}
{{- $registry := "ghcr.io/bouc-io" -}}
{{- if hasKey .Values.image "registry" -}}{{- $registry = .Values.image.registry -}}{{- end -}}
{{- if $global.imageRegistry -}}{{- $registry = $global.imageRegistry -}}{{- end -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $repo := .Values.image.repository -}}
{{/* Back-compat: a repository that already carries a registry host (the pre-split
     full-string form) is used verbatim, so old values never get a doubled prefix. */}}
{{- $head := splitList "/" $repo | first -}}
{{- if or (contains "." $head) (contains ":" $head) -}}
{{- $registry = "" -}}
{{- end -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}

{{/*
Image pull secrets: global.imagePullSecrets concatenated with imagePullSecrets.
*/}}
{{- define "agent-api-chart.imagePullSecrets" -}}
{{- $global := .Values.global | default dict -}}
{{- concat ($global.imagePullSecrets | default list) (.Values.imagePullSecrets | default list) | toYaml -}}
{{- end }}
