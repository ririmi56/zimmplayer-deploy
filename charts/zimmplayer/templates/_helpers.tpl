{{- define "zimmplayer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zimmplayer.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "zimmplayer.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "zimmplayer.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "zimmplayer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "zimmplayer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zimmplayer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "zimmplayer.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}

{{/*
Politique de tirage des images.

Un tag MOUVANT (`latest`, ou tout `*-dev`) pointe un contenu different d'un
jour a l'autre. Avec `IfNotPresent`, le noeud garde indefiniment la premiere
image tiree sous ce nom : aucun `helm upgrade` ne la remplace, et l'on croit
tester la derniere version alors qu'on execute celle d'il y a trois jours.
C'est arrive le 2026-09-01.

Un tag de version, lui, est immuable : `IfNotPresent` evite alors de retirer
des centaines de mega-octets a chaque demarrage de pod — ce qui compte sur un
reseau airgap.

`image.pullPolicy` renseigne explicitement l'emporte sur ce choix.
*/}}
{{- define "zimmplayer.pullPolicy" -}}
{{- $tag := include "zimmplayer.imageTag" . -}}
{{- if .Values.image.pullPolicy -}}
{{- .Values.image.pullPolicy -}}
{{- else if or (eq $tag "latest") (hasSuffix "-dev" $tag) -}}
Always
{{- else -}}
IfNotPresent
{{- end -}}
{{- end -}}

{{- define "zimmplayer.secretName" -}}
{{- printf "%s-secrets" (include "zimmplayer.fullname" .) -}}
{{- end -}}

{{/*
Service sans ClusterIP de l'API.

C'est l'adresse que l'API annonce a snapserver pour qu'il vienne chercher le
flux de chaque session. Elle doit resoudre vers l'IP du POD et non vers une
IP de service : snapserver ouvre une connexion TCP sur une plage de ports que
le Service ne declare pas.
*/}}
{{- define "zimmplayer.apiDirectService" -}}
{{- printf "%s-api-direct" (include "zimmplayer.fullname" .) -}}
{{- end -}}

{{- define "zimmplayer.snapserverService" -}}
{{- printf "%s-snapserver" (include "zimmplayer.fullname" .) -}}
{{- end -}}

{{/*
Chemin de l'autorite de certification interne montee dans les conteneurs, ou
la chaine vide si aucune n'est fournie.
*/}}
{{- define "zimmplayer.caPath" -}}
{{- if or .Values.tls.existingSecret .Values.tls.existingConfigMap -}}
{{- printf "/etc/zimmplayer/ca/%s" .Values.tls.key -}}
{{- end -}}
{{- end -}}

{{/*
Volume et montage de cette autorite, repris par l'API comme par le front.
*/}}
{{- define "zimmplayer.caVolume" -}}
{{- if .Values.tls.existingSecret }}
- name: ca
  secret:
    secretName: {{ .Values.tls.existingSecret }}
{{- else if .Values.tls.existingConfigMap }}
- name: ca
  configMap:
    name: {{ .Values.tls.existingConfigMap }}
{{- end }}
{{- end -}}

{{- define "zimmplayer.caVolumeMount" -}}
{{- if or .Values.tls.existingSecret .Values.tls.existingConfigMap }}
- name: ca
  mountPath: /etc/zimmplayer/ca
  readOnly: true
{{- end }}
{{- end -}}
