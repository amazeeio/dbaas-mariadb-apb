# MariaDB as a Service APB

This Ansible playbook bundle provisions users and databases on a existing MariaDB instance.

## Installation
Set up the Ansible service broker to import APBs from the Docker Hub appuio repository:
```yaml
registry:
  - name: lagoon
    type: dockerhub
    org: lagoonapb
    tag: latest
    white_list: [.*-apb$]
```

To provide the admin user credentials to connect to the MariaDB, two secrets with the name `dbaas-db-credentials-production` and `dbaas-db-credentials-development` needs to exist in the Ansible service broker namespace:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dbaas-db-credentials-production
type: Opaque
stringData:
  mariadb_hostname: db.maria.com
  mariadb_reader_hostname: db.reader.maria.com
  mariadb_password: myPassword
  mariadb_port: '3306'
  mariadb_user: root
```
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dbaas-db-credentials-development
type: Opaque
stringData:
  mariadb_hostname: db.maria.com
  mariadb_reader_hostname: db.reader.maria.com
  mariadb_password: myPassword
  mariadb_port: '3306'
  mariadb_user: root
```
The Ansible service broker needs to be configured to mount the secret in provisioner pods. Add the following section to the Ansible service broker configuration (ConfigMap):
```yaml
secrets:
- title: DBaaS database credentials
  secret: dbaas-db-credentials-production
  apb_name: lagoon-dbaas-mariadb-apb
- title: DBaaS database credentials
  secret: dbaas-db-credentials-development
  apb_name: lagoon-dbaas-mariadb-apb
```

## Development environment
You can use [minishift](https://github.com/minishift/minishift) with the [Ansible Service Broker Addon](https://github.com/minishift/minishift-addons/tree/master/add-ons/ansible-service-broker) to run a local OpenShift installation with the Ansible service broker to test APBs:
```bash
MINISHIFT_ENABLE_EXPERIMENTAL=y minishift start --extra-clusterup-flags "--service-catalog" --openshift-version v3.9.0

minishift addons install <path_to_addon>
minishift addons apply ansible-service-broker
```

Install the [APB CLI](https://github.com/ansibleplaybookbundle/ansible-playbook-bundle/blob/master/docs/apb_cli.md#installing-the-apb-tool) on your machine. The easiest way is to run it in a Docker container via the provided [helper script](https://github.com/ansibleplaybookbundle/ansible-playbook-bundle/blob/master/scripts/apb-docker-run.sh).

## Release
An automatic Docker build is set up for this repository. If you change stuff in `apb.yml` don't forget to run `apb prepare` before committing.

## Reader configuration
If the mariadb/mysql supports a reader instance aswell as a writer, you can configure the `mariadb_reader_hostname` to point to the endpoint for a reader, otherwise just populate it with the same value as the `mariadb_hostname` if one is not available
