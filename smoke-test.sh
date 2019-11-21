#!/usr/bin/env bats

# this script can be run on a live cluster to test provisioning/deprovisioning
#
# NOTE: please run this in a new namespace. e.g. run this first:
#
# 	oc new-project test-dbaas


# helper functions

provision() {
	run svcat provision test-dbaas \
		--class lagoon-dbaas-mariadb-apb \
		--plan $1 \
		--wait
	echo "$output"
	[[ $status -eq 0 ]]
}

bind() {
	run svcat bind test-dbaas \
		--name test-dbaas-binding \
		--secret-name test-dbaas-secret \
		--wait
	echo "$output"
	[[ $status -eq 0 ]]
}

check_secret() {
	run bash -c '
			set -euo pipefail
			data=$(oc get secret test-dbaas-secret -o json --export | jq -e ".data")
			echo Secret data:
			echo "$data"
			echo "$data" | jq -e "select(
				.DB_HOST? and
				.DB_READREPLICA_HOSTS? and
				.DB_NAME? and
				.DB_PASSWORD? and
				.DB_PORT? and
				.DB_TYPE? and
				.DB_USER?
				)"
		'
	echo "$output"
	[[ $status -eq 0 ]]
}

unbind() {
	run svcat unbind test-dbaas \
		--wait
	echo "$output"
	[[ $status -eq 0 ]]
}

deprovision() {
	run svcat deprovision test-dbaas \
		--wait
	echo "$output"
	[[ $status -eq 0 ]]
}

# test cases (run sequentially)

@test "provision a service (development)" {
	provision development
}
@test "bind the secret (development)" {
	bind
}
@test "check the contents of the secret (development)" {
	check_secret
}
@test "unbind the secret (development)" {
	unbind
}
@test "deprovision the service (development)" {
	deprovision
}

@test "provision a service (production)" {
	provision production
}
@test "bind the secret (production)" {
	bind
}
@test "check the contents of the secret (production)" {
	check_secret
}
@test "unbind the secret (production)" {
	unbind
}
@test "deprovision the service (production)" {
	deprovision
}
