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
sudo nano zabbix.env
#Compléter les scripts et le fichier .env
```
Lancer l'installation
```
chmod +x install_depencies_env.sh install_zabbix_env.sh
sudo bash install_depencies_env.sh
"..." install_zabbix_env.sh
```
Le script "install_zabbix_env.sh" fonctionne de paire avec le fichier "zabbix.env" contenant les valeurs nécessaires à l'installation :

- SERVER_NAME
- DB_NAME
- DB_USER
- DB_PASSWORD

### On stage environment
## Directory structure

Here you are a sample of project structure. It's must be adapted to your stack.

```shell
project-root/
├── README.md
├── .env.example              # environment variables template

├── config/                   # configuration (per environment)
│   ├── dev.env
│   ├── staging.env

├── bin/                      # entrypoints (what you actually run)
│   ├── deploy.sh
│   └── status.sh

├── lib/                      # shared logic (like "modules")
│   ├── log.sh
│   ├── utils.sh
│   ├── checks.sh             # preflight checks
│   └── state.sh              # poor man's state management

├── scripts/                  # helpers (optional)
│   ├── zabbix_deployment
|   ├── agent_deployment
|       ├── linux
|       ├── windows
│       ├── docker
|   └── lint.sh
```

## Collaborate

* How to propose a new feature (issue, pull request)
* [How to commit](https://www.conventionalcommits.org/en/v1.0.0/)
* [How to use your workflow](https://nvie.com/posts/a-successful-git-branching-model/)

## License

* [Choose the license adapted to your project](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

## Contact

* How to get in contact with you? Discord, Trello, Issue?

## Script Agent
# Zabbix Agent 2 — Installation

## Fichiers

```
.env                              → Config Linux
.env.windows.txt                  → Config Windows
install_zabbix_agent_linux.sh     → Installation Linux
validate_zabbix_linux.sh          → Validation Linux
install_zabbix_agent_windows.ps1  → Installation Windows
validate_zabbix_windows.ps1       → Validation Windows
```

---

## Configuration

Remplis le `.env` (Linux) ou `.env.windows.txt` (Windows) avec ton IP serveur, le hostname et le token API, puis ouvre le port **10050/tcp** dans le Security Group AWS de l'instance.

---

## Linux

```bash
# Copier les fichiers sur l'instance
scp -i ta-cle.pem .env install_zabbix_agent_linux.sh validate_zabbix_linux.sh ec2-user@<IP>:~/

# Se connecter
ssh -i ta-cle.pem ec2-user@<IP>

# Installer
chmod +x install_zabbix_agent_linux.sh validate_zabbix_linux.sh
sudo ./install_zabbix_agent_linux.sh

# Valider
sudo ./validate_zabbix_linux.sh
```

---

## Windows

```powershell
# Ouvrir PowerShell en Administrateur
# Se placer dans le dossier des scripts, puis :

Set-ExecutionPolicy Bypass -Scope Process -Force
.\install_zabbix_agent_windows.ps1

# Valider
.\validate_zabbix_windows.ps1
```

---

## Erreurs fréquentes

| Erreur | Solution |
|---|---|
| `Fichier .env introuvable` | Lance le script depuis le dossier où se trouve le `.env` |
| `Port 10051 inaccessible` | Ouvre le port 10051/tcp entrant sur le Security Group du serveur Zabbix |
| `Hôte non créé via API` | Vérifie le token dans `Administration > Users > API tokens` |
