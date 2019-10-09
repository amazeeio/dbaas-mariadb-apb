# MariaDB as a Service APB

This Ansible Playbook Bundle (APB) provisions users and databases on a existing MariaDB instance.

## Installation

Set up the Ansible service broker to import APBs from the Docker Hub appuio repository:

```yaml
registry:
  - name: amazeeiolagoon
    type: dockerhub
    org: amazeeiolagoon
    tag: latest
    white_list: [.*-apb$]
```

To provide the admin user credentials to connect to the MariaDB, a secret with the name `dbaas-db-credentials` needs to exist in the Ansible service broker namespace:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dbaas-db-credentials-production
type: Opaque
stringData:
  production_mariadb_hostname: db.maria.com
  production_mariadb_readreplica_hostname: db.readreplica.maria.com
  production_mariadb_password: myPassword
  production_mariadb_port: '3306'
  production_mariadb_user: root
  development_mariadb_hostname: db.maria.com
  development_mariadb_readreplica_hostname: db.readreplica.maria.com
  development_mariadb_password: myPassword
  development_mariadb_port: '3306'
  development_mariadb_user: root
```

If your environment has a read-replica mariadb endpoint, you can configure `*_mariadb_readreplica_hostname` with the read-replica hostname.
Otherwise, if there is no read-replica available, just populate it with the same value as `*_mariadb_hostname`.

The Ansible service broker needs to be configured to mount the secret in provisioner pods. Add the following section to the Ansible service broker configuration (ConfigMap):

```yaml
secrets:
- title: DBaaS database credentials
  secret: dbaas-db-credentials
  apb_name: lagoon-dbaas-mariadb-apb
```

## Development environment

*NOTE: these scripts run `oc` commands, so don't run them while logged in to another cluster*

You can use [minishift](https://github.com/minishift/minishift) with the [Ansible Service Broker Addon](https://github.com/minishift/minishift-addons/tree/master/add-ons/ansible-service-broker) to run a local OpenShift installation with the Ansible service broker to test APBs.

The script `minishift-devel.sh` will set up a minishift development environment for you.
It requires these CLI tools to be installed:

* [oc](https://github.com/openshift/origin/releases)
* [apb](https://github.com/automationbroker/apb/releases)
* [helm](https://github.com/helm/helm/releases)

Also refer to the `apb` [developer documentation](https://github.com/automationbroker/apb/blob/master/docs/developers.md), and the other documents in that `/docs` directory.

### Tests

Basic integration tests can be run using `minishift-test.sh`, and assume an environment set up via the `minishift-devel.sh` script.
The tests require these CLI tools to be installed:

* [bats](https://github.com/bats-core/bats-core)
* [svcat](https://github.com/kubernetes-sigs/service-catalog/releases)

Example test output:

```
$ ./minishift-test.sh
 ✓ provision a service (development)
 ✓ bind the secret (development)
 ✓ check the contents of the secret (development)
 ✓ unbind the secret (development)
 ✓ deprovision the service (development)
 ✓ provision a service (production)
 ✓ bind the secret (production)
 ✓ check the contents of the secret (production)
 ✓ unbind the secret (production)
 ✓ deprovision the service (production)

10 tests, 0 failures
```

### Local development workflow

```bash
# hack
...
# push
oc start-build -n openshift --follow --from-dir . dbaas-mariadb-apb
# test
svcat provision test-dbaas --class localregistry-dbaas-mariadb-apb --plan development --wait
svcat deprovision test-dbaas --class localregistry-dbaas-mariadb-apb --plan development --wait
```

## Release

An automatic Docker build is set up for this repository. If you change stuff in `apb.yml` don't forget to run `apb prepare` before committing.

