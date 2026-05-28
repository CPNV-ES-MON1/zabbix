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
Le script "install_zabbix_env.sh" demandera interactivement :
* Le nom de machine
* Le nom de la base de données
* L'utilisateur MariaDB
* Le mot de passe MariaDB

### On stage environment

#### Emplacement logs dépendances
Pour afficher les logs, insérer avant "sudo tail -f"
## Logs des services

### Identification des logs

| Service | Fichier |
|---|---|
| Zabbix Server | `/var/log/zabbix/zabbix_server.log` |
| Zabbix Agent2 | `/var/log/zabbix/zabbix_agent2.log` |
| Apache (accès) | `/var/log/apache2/access.log` |
| Apache (erreurs) | `/var/log/apache2/error.log` |
| MariaDB | `sudo journalctl -u mariadb` |
| Système | `/var/log/syslog` |

### Contenu des logs

- **Zabbix Server** : démarrage/arrêt, connexions BDD, erreurs de collecte, alertes
- **Zabbix Agent2** : métriques collectées, connexions serveur, erreurs d'items
- **Apache access.log** : requêtes HTTP vers l'interface web (IP, URL, code réponse)
- **Apache error.log** : erreurs PHP, pages introuvables, problèmes de config
- **MariaDB** : démarrage/arrêt, erreurs de requêtes, problèmes de connexion
- **Syslog** : logs système globaux (kernel, services, authentification)

```bash
# Vérifier la config de rotation Zabbix
cat /etc/logrotate.d/zabbix-server
# Vérifier la config de rotation Apache
cat /etc/logrotate.d/apache2
# Vérifier la config de rotation MariaDB
cat /etc/logrotate.d/mysql-server
# Tester que logrotate fonctionne
sudo logrotate --debug /etc/logrotate.conf
```
### Niveau de verbosité
**Zabbix Server** - `/etc/zabbix/zabbix_server.conf` - [Debug Level Zabbix](https://www.zabbix.com/documentation/7.0/en/manual/appendix/config/zabbix_server)
```
# 0=désactivé, 1=critique, 2=erreur, 3=warning, 4=debug, 5=trace
DebugLevel=3
```
```bash
sudo systemctl restart zabbix-server
```
**Apache** - `/etc/apache2/apache2.conf` - [Apache](https://httpd.apache.org/docs/2.4/mod/core.html#loglevel)
```
# emerg / alert / crit / error / warn / notice / info / debug
LogLevel warn
```
```bash
sudo systemctl restart apache2
```
**MariaDB** - `/etc/mysql/mariadb.conf.d/50-server.cnf` - [Log Warnings MariaDB](https://mariadb.com/docs/server/server-management/variables-and-modes/server-system-variables#log_warnings)
```
# 1=erreurs, 2=warnings, 3=infos
log_warnings = 2
```
```bash
sudo systemctl restart mariadb
```


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
