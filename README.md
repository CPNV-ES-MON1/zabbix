# ZABBIX

## Description

### Prérequis
|Rôle|Outil|Version|
|:--|:--|:--|
|VCS|Git SCM|[2.54 or higher](https://git-scm.com/install/)|
|IaC|Terraform|[1.15 or higher](https://developer.hashicorp.com/terraform/install)|
|IDE|VS Code|[1.118 or higher](https://code.visualstudio.com/thank-you?dv=linux64_deb)|
|Virtualization|Docker Engine|[v29 or higher](https://docs.docker.com/engine/install/)|
### Prérequis installation Zabbix
|Rôle|Outil|Version|Lien|
|:--|:--|:--|:--|
|Monitoring|Zabbix Server|7.0|[Zabbix](https://www.zabbix.com/life_cycle_and_release_policy)|
|Database|MariaDB|10.11|[MariaDB](https://mariadb.com/docs/release-notes/community-server/10.11/what-is-mariadb-1011)|
|Web Server|Apache|2.4|[Apache](https://httpd.apache.org/download.cgi)|
|Language|PHP|8.2|[PHP](https://www.zabbix.com/documentation/7.0/en/manual/installation/requirements)

### Configuration

## Deployment
### Logs
### On dev environment
Créer les scripts
```
sudo nano install_depencies_env.sh
"..." install_zabbix_env.sh
"..." main.sh
#Compléter les scripts
```
Lancer l'installation
```
chmod +x main.sh install_depencies_env.sh install_zabbix_env.sh
sudo bash main.sh
```
### On stage environment

#### Emplacement logs dépendances
Pour afficher les logs, insérer avant "sudo tail -f"
| Service | Fichier |
|:--|:--|
| Zabbix Server | `/var/log/zabbix/zabbix_server.log` |
| Zabbix Agent2 | `/var/log/zabbix/zabbix_agent2.log` |
| Apache (accès) | `/var/log/apache2/access.log` |
| Apache (erreurs) | `/var/log/apache2/error.log` |
| MariaDB | `/var/log/mysql/error.log` |
| Système | `/var/log/syslog` |

Update all variable according to your setup.

## Directory structure

Here you are a sample of project structure. It's must be adapted to your stack.

```shell
project-root/
├── README.md
├── .env.example              # environment variables template

├── config/                   # configuration (per environment)
│   ├── dev.env
│   ├── staging.env
│   └── prod.env

├── bin/                      # entrypoints (what you actually run)
│   ├── deploy.sh
│   ├── destroy.sh
│   └── status.sh

├── lib/                      # shared logic (like "modules")
│   ├── log.sh
│   ├── utils.sh
│   ├── checks.sh             # preflight checks
│   └── state.sh              # poor man's state management

├── services/                 # components of your stack
│   ├── network/
│   │   ├── create.sh
│   │   └── destroy.sh
│   │
│   ├── compute/
│   │   ├── create.sh
│   │   └── destroy.sh
│   │
│   ├── monitoring/
│   │   ├── prometheus.sh
│   │   ├── grafana.sh
│   │   └── alertmanager.sh
│   │
│   └── security/
│       ├── iam.sh
│       └── secrets.sh

├── state/                    # local state tracking
│   └── deployed.json

├── scripts/                  # helpers (optional)
│   ├── install_deps.sh
│   └── lint.sh

└── logs/
    └── deploy.log
```

## Collaborate

* How to propose a new feature (issue, pull request)
* [How to commit](https://www.conventionalcommits.org/en/v1.0.0/)
* [How to use your workflow](https://nvie.com/posts/a-successful-git-branching-model/)

## License

* [Choose the license adapted to your project](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

## Contact

* How to get in contact with you? Discord, Trello, Issue?
