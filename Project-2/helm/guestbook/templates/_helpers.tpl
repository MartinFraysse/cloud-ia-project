{{/*
_helpers.tpl — les "fonctions" du chart, écrites UNE seule fois et appelées par les autres
templates avec : include "<nom>" <paramètres>
Le "_" au début du nom : Helm ne transforme pas ce fichier en objet Kubernetes.
Le préfixe "guestbook." évite les conflits de noms avec d'autres charts.

  ① LES NOMS DE BASE       guestbook.name, guestbook.fullname, guestbook.chart   (exigence H4)
  ② LES LABELS             guestbook.selectorLabels, guestbook.labels,
                           guestbook.componentSelectorLabels, guestbook.componentLabels   (H4)
  ③ LES NOMS DES OBJETS    guestbook.componentName, guestbook.*.serviceName,
                           guestbook.redisLeader.pvcName                         (exigence H3)
*/}}


{{/* ======================================================================
     ① LES NOMS DE BASE
     ====================================================================== */}}

{{/* Nom du chart : "guestbook" (ou nameOverride). 63 caractères max = limite Kubernetes. */}}
{{- define "guestbook.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Nom complet : "<release>-guestbook" (ou fullnameOverride).
     C'est le nom de la release qui sépare les environnements. */}}
{{- define "guestbook.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "guestbook.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* "<chart>-<version>", ex. "guestbook-0.1.0" : valeur du label helm.sh/chart. */}}
{{- define "guestbook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/* ======================================================================
     ② LES LABELS
     ====================================================================== */}}

{{/* Labels STABLES, pour les sélecteurs. Ni version ni chart : le sélecteur d'un
     Deployment ne peut plus changer après création, sinon le helm upgrade échoue. */}}
{{- define "guestbook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "guestbook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Labels COMMUNS, posés sur tous les objets : les labels stables + les autres
     + les commonLabels du fichier de valeurs (ex. environment: <ENV>). */}}
{{- define "guestbook.labels" -}}
helm.sh/chart: {{ include "guestbook.chart" . }}
{{ include "guestbook.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.partOf }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Les mêmes, avec en plus le label du composant (frontend | redis-leader | redis-follower).
     Appel : include "guestbook.componentLabels" (dict "ctx" . "component" "frontend")
     dict sert à passer 2 paramètres : ctx = le contexte (.), component = le composant. */}}
{{- define "guestbook.componentSelectorLabels" -}}
{{ include "guestbook.selectorLabels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "guestbook.componentLabels" -}}
{{ include "guestbook.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}


{{/* ======================================================================
     ③ LES NOMS DES OBJETS
     ====================================================================== */}}

{{/* Nom d'un objet : "<release>-guestbook-<composant>".
     Appel : include "guestbook.componentName" (dict "ctx" . "component" "frontend") */}}
{{- define "guestbook.componentName" -}}
{{- printf "%s-%s" (include "guestbook.fullname" .ctx) .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Noms des 3 Services : <composant>.service.name s'il est renseigné, sinon le nom calculé.
     Définis UNE fois, utilisés par le Service ET par les ConfigMaps qui y font référence
     (REDIS_*_SERVICE_HOST) : les deux ne peuvent pas être différents. */}}
{{- define "guestbook.frontend.serviceName" -}}
{{- default (include "guestbook.componentName" (dict "ctx" . "component" "frontend")) .Values.frontend.service.name }}
{{- end }}

{{- define "guestbook.redisLeader.serviceName" -}}
{{- default (include "guestbook.componentName" (dict "ctx" . "component" "redis-leader")) .Values.redisLeader.service.name }}
{{- end }}

{{- define "guestbook.redisFollower.serviceName" -}}
{{- default (include "guestbook.componentName" (dict "ctx" . "component" "redis-follower")) .Values.redisFollower.service.name }}
{{- end }}

{{/* Nom du PVC du leader : "<release>-guestbook-redis-leader-data".
     Utilisé par le PVC ET par le Deployment du leader (claimName). */}}
{{- define "guestbook.redisLeader.pvcName" -}}
{{- printf "%s-data" (include "guestbook.componentName" (dict "ctx" . "component" "redis-leader")) }}
{{- end }}
