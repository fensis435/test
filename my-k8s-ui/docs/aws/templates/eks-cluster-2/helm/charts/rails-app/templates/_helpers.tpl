{{/*
rails-app/templates/_helpers.tpl
*/}}
{{- define "rails-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "rails-app.fullname" -}}
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

{{- define "rails-app.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "rails-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "rails-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rails-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
共通環境変数
*/}}
{{- define "rails-app.commonEnv" -}}
- name: RAILS_ENV
  value: {{ .Values.env.RAILS_ENV | quote }}
- name: RAILS_LOG_TO_STDOUT
  value: {{ .Values.env.RAILS_LOG_TO_STDOUT | quote }}
- name: RAILS_SERVE_STATIC_FILES
  value: {{ .Values.env.RAILS_SERVE_STATIC_FILES | quote }}
- name: PORT
  value: {{ .Values.env.PORT | quote }}
- name: WEB_CONCURRENCY
  value: {{ .Values.env.WEB_CONCURRENCY | quote }}
- name: RAILS_MAX_THREADS
  value: {{ .Values.env.RAILS_MAX_THREADS | quote }}
- name: DATABASE_HOST
  value: {{ .Values.env.DATABASE_HOST | quote }}
- name: DATABASE_PORT
  value: {{ .Values.env.DATABASE_PORT | quote }}
- name: DATABASE_NAME
  value: {{ .Values.env.DATABASE_NAME | quote }}
- name: DATABASE_SSLMODE
  value: {{ .Values.env.DATABASE_SSLMODE | quote }}
- name: AWS_REGION
  value: {{ .Values.global.awsRegion | quote }}
- name: SQS_QUEUE_URL
  value: {{ .Values.env.SQS_QUEUE_URL | quote }}
- name: COGNITO_USER_POOL_ID
  value: {{ .Values.env.COGNITO_USER_POOL_ID | quote }}
- name: COGNITO_CLIENT_ID
  value: {{ .Values.env.COGNITO_CLIENT_ID | quote }}
- name: COGNITO_ISSUER
  value: {{ .Values.env.COGNITO_ISSUER | quote }}
- name: COGNITO_JWKS_URI
  value: {{ .Values.env.COGNITO_JWKS_URI | quote }}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
{{- end }}
