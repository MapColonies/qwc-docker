{{- define "qwc-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "qwc-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "qwc-service.image" -}}
{{- if .Values.global.cloudProvider.dockerRegistryUrl -}}
{{- printf "%s/%s:%s" .Values.global.cloudProvider.dockerRegistryUrl .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "qwc-service.sharedPvc" -}}
{{- if .Values.global.sharedStorage.existingClaim -}}
{{- .Values.global.sharedStorage.existingClaim -}}
{{- else -}}
{{- printf "%s-shared" .Release.Name -}}
{{- end -}}
{{- end -}}
