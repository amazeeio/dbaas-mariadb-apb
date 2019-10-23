#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ -z "$KUBECONFIG" ]] || [[ $(realpath "$KUBECONFIG") = $(realpath "$HOME/.kube/config") ]]; then
	echo -e '\nThis script runs oc commands, and you are using the global ~/.kube/config.' \
		'If you are okay with this, hit enter to confirm.' \
		'Or use an alternative $KUBECONFIG.\n'\
		'e.g. export KUBECONFIG=$(mktemp --tmpdir kubeconfig.XXXXXXXX)\n'
	read
fi

# start minishift with the appropriate components
minishift --profile dbaas-test start --cpus=4 --memory=8GB
minishift --profile dbaas-test openshift component add service-catalog
minishift --profile dbaas-test openshift component add automation-service-broker

# give developer cluster-admin for apb builds/installs
oc login -u system:admin
oc adm policy add-cluster-role-to-user cluster-admin developer
oc login -u developer
# perform build
oc new-build -n openshift --binary=true --name dbaas-mariadb-apb
oc start-build -n openshift --follow --from-dir . dbaas-mariadb-apb

# wait for ASB to be deployed
while oc get pod -n openshift-automation-service-broker | grep deploy > /dev/null; do
	sleep 5
done

# notify the broker to search for available APBs
# this executes asynchronously and may take a minute to finish
while ! apb --kubeconfig="$KUBECONFIG" broker bootstrap; do
	sleep 5
done
# verify that the broker found the new APB
while ! apb --kubeconfig="$KUBECONFIG" broker catalog | grep dbaas-mariadb; do
	sleep 5
done
# notify the service catalog web UI to update its catalog
apb --kubeconfig="$KUBECONFIG" catalog relist

# install the mariadb cluster
export TILLER_NAMESPACE=tiller
oc new-project $TILLER_NAMESPACE
export HELM_VERSION=v2.14.3 # get this from: helm -c --short
oc process -f https://github.com/openshift/origin/raw/master/examples/helm/tiller-template.yaml -p TILLER_NAMESPACE="${TILLER_NAMESPACE}" -p HELM_VERSION="${HELM_VERSION}" | oc create -f -
while ! oc get pod -n tiller | grep '1/1'; do
	sleep 5
done
oc new-project mariadb-cluster
oc adm policy add-scc-to-user anyuid -z default
oc policy add-role-to-user cluster-admin "system:serviceaccount:${TILLER_NAMESPACE}:tiller"
helm install --name dbcluster stable/mariadb

# bind the secrets into deployment pods
updatedBrokerConfig=$(
	# get the current configmap
	oc -n openshift-automation-service-broker get cm broker-config -o json --export |
	# pull out the broker-config field, which is raw YAML
	jq -r '.data."broker-config"' |
	# translate this YAML to JSON
	ruby -ryaml -rjson -e 'puts YAML.load(ARGF).to_json' |
	# append the secrets config to this JSON
	jq '. += {secrets: [{title: "DBaaS database credentials", secret: "lagoon-dbaas-db-credentials", apb_name: "localregistry-dbaas-mariadb-apb"}]}' |
	# convert back to YAML
	ruby -ryaml -rjson -e 'puts JSON.load(ARGF).to_yaml' |
	# escape the double quotes in preparation for insertion back into the configmap
	sed 's/"/\\"/g'
)
# replace the existing configmap with the new one containing the secrets binding
oc -n openshift-automation-service-broker get cm broker-config -o json --export | jq -r ".data.\"broker-config\" = \"$updatedBrokerConfig\"" | oc -n openshift-automation-service-broker replace -f -
# rollout the service with the new configmap
oc -n openshift-automation-service-broker rollout latest dc/openshift-automation-service-broker
# wait on the rollout
oc -n openshift-automation-service-broker rollout status dc/openshift-automation-service-broker

mariadb_root_password=$(oc -n mariadb-cluster get secret dbcluster-mariadb -o json | jq -r '.data."mariadb-root-password"' | base64 -d)

# insert the required secrets into the right place
oc -n openshift-automation-service-broker apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: lagoon-dbaas-db-credentials
type: Opaque
stringData:
  production_mariadb_hostname: dbcluster-mariadb.mariadb-cluster.svc.cluster.local
  production_mariadb_readreplica_hostname: dbcluster-mariadb.mariadb-cluster.svc.cluster.local
  production_mariadb_password: $mariadb_root_password
  production_mariadb_port: '3306'
  production_mariadb_user: root
  development_mariadb_hostname: dbcluster-mariadb.mariadb-cluster.svc.cluster.local
  development_mariadb_readreplica_hostname: dbcluster-mariadb.mariadb-cluster.svc.cluster.local
  development_mariadb_password: $mariadb_root_password
  development_mariadb_port: '3306'
  development_mariadb_user: root
EOF

# switch back to myproject
oc project myproject
