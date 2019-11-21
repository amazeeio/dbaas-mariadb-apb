#!/usr/bin/env bats

# helper functions

provision() {
	oc new-project "test-dbaas-$1-$(
		LC_CTYPE=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 8 | head -n 1)"
	run svcat provision test-dbaas \
		--class localregistry-dbaas-mariadb-apb \
		--plan $1 \
		--wait
	echo "$output"
	[[ $status -eq 0 ]]
}

provision_without_readreplica_secret() {
	# remove readreplica secret
	oc -n openshift-automation-service-broker get secret \
	lagoon-dbaas-db-credentials -o json --export | \
	jq 'del(.data.development_mariadb_readreplica_hostname,
			.data.production_mariadb_readreplica_hostname)' | \
	oc -n openshift-automation-service-broker apply -f - --wait

	provision "$1"

	# replace readreplica secret
	oc -n openshift-automation-service-broker get secret \
	lagoon-dbaas-db-credentials -o json --export | \
	jq '.data.production_mariadb_readreplica_hostname =
			.data.production_mariadb_hostname |
			.data.development_mariadb_readreplica_hostname =
			.data.development_mariadb_hostname' | \
	oc -n openshift-automation-service-broker apply -f - --wait
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

check_secret_without_readreplica() {
	# the DB_READREPLICA_HOSTS secret in the project should be empty
	check_secret
	run bash -c '
			set -euo pipefail
			db_readreplica_host=$(oc get secret test-dbaas-secret --export \
				--output="jsonpath={.data.DB_READREPLICA_HOSTS}")
			echo "$db_readreplica_host"
			[[ -z "$db_readreplica_host" ]]
		'
	echo "$output"
	[[ $status -eq 0 ]]
}

check_username_prefix() {
	run bash -c '
			set -euo pipefail
			namespace=$(oc config view --minify --output="jsonpath={..namespace}")
			db_user=$(oc get secret test-dbaas-secret -o json --export |
				jq -re ".data.DB_USER" | base64 -d)
			echo "$db_user"
			echo "$db_user" | grep "^$(printf "%.10s" "$namespace")_" > /dev/null
		'
	echo "$output"
	[[ $status -eq 0 ]]
}

check_username_length() {
	run bash -c '
			set -euo pipefail
			db_user=$(oc get secret test-dbaas-secret --export \
				--output="jsonpath={.data.DB_USER}" | base64 -d)
			echo "$db_user"
			echo -n "$db_user" | grep -E "^.{,16}$" > /dev/null
		'
	echo "$output"
	[[ $status -eq 0 ]]
}

# takes a single "true" or "false" argument that determines if the function
# checks for the existence or not of the readreplica service
check_readreplica_service() {
	run bash -c '
			set -euo pipefail
			readreplica_service=$(oc get services | grep readreplica || :)
			echo "$readreplica_service"
			if $0; then
				[[ "$readreplica_service" ]]
			else
				[[ -z "$readreplica_service" ]]
			fi' "$1"
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
@test "check that the readreplica service is defined (development)" {
	check_readreplica_service true
}
@test "bind the secret (development)" {
	bind
}
@test "check the contents of the secret (development)" {
	check_secret
}
@test "check that the username prefix matches the namespace (development)" {
	check_username_prefix
}
@test "check that the username is <= 16 chars (development)" {
	check_username_length
}
@test "unbind the secret (development)" {
	unbind
}
@test "deprovision the service (development)" {
	deprovision
}

@test "provision without the readreplica secret present (development)" {
	provision_without_readreplica_secret development
}
@test "check that no readreplica service is defined (development)" {
	check_readreplica_service false
}
@test "bind the secret without the readreplica (development)" {
	bind
}
@test "check the contents of the secret without the readreplica (development)" {
	check_secret_without_readreplica
}
@test "unbind the secret without the readreplica (development)" {
	unbind
}
@test "deprovision without the readreplica secret present (development)" {
	deprovision
}


@test "provision a service (production)" {
	provision production
}
@test "check that the readreplica service is defined (production)" {
	check_readreplica_service true
}
@test "bind the secret (production)" {
	bind
}
@test "check the contents of the secret (production)" {
	check_secret
}
@test "check that the username prefix matches the namespace (production)" {
	check_username_prefix
}
@test "check that the username is <= 16 chars (production)" {
	check_username_length
}
@test "unbind the secret (production)" {
	unbind
}
@test "deprovision the service (production)" {
	deprovision
}

@test "provision without the readreplica secret present (production)" {
	provision_without_readreplica_secret production
}
@test "check that no readreplica service is defined (production)" {
	check_readreplica_service false
}
@test "bind the secret without the readreplica (production)" {
	bind
}
@test "check the contents of the secret without the readreplica (production)" {
	check_secret_without_readreplica
}
@test "unbind the secret without the readreplica (production)" {
	unbind
}
@test "deprovision without the readreplica secret present (production)" {
	deprovision
}
