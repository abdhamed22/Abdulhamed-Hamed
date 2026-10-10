# Abdulhameed Hameed: CV website

Personal CV site for **Abdulhameed Hameed**, Network & Systems Engineer growing into Cloud & DevOps.

**Live site:** https://cv.u-network-it.com

It's a plain static site (HTML, CSS and a little JavaScript) with no build step. It includes light and dark themes, a mobile layout, and a downloadable PDF CV.

## Structure

```
site/                             # the website (this folder is what gets deployed)
├── index.html                    # all page content lives here
└── assets/
    ├── css/style.css             # theme colors are variables at the top
    ├── js/main.js                # light/dark toggle (the only script)
    ├── img/profile.jpg|.webp     # profile photo (720x720)
    ├── img/favicon.svg
    └── Abdulhameed_Hameed_CV.pdf # the "Download CV" file
deploy/server-setup.sh            # one-time server setup (Apache vhost + deploy user)
.github/workflows/deploy.yml      # CI/CD: validate, then deploy to the server
```

## How deployment works

```
git push (main) ──► GitHub Actions
                     ├─ validate: html-validate, asset check, shellcheck
                     └─ deploy:   rsync over SSH ──► Vultr VPS (Ubuntu, Apache)
                                                      /var/www/cv.u-network-it.com
                                                            ▲
                     visitors ──► Cloudflare (proxy, TLS) ──┘
```

- The deploy uses a dedicated `cvdeploy` user. Its SSH key is locked with `rrsync -wo`, so it can only **write files into the web root**: no shell, no reading, no other paths.
- The server's host key is pinned in the `SSH_KNOWN_HOSTS` secret.
- Asset links carry `?v=<commit>`, so Cloudflare and browsers fetch fresh CSS/JS after every deploy.
- After uploading, the pipeline checks that the live site serves the new version.

## One-time setup

### 1. Cloudflare DNS

Add a DNS record: **Type** `A`, **Name** `cv`, **IPv4** your server IP, **Proxy status** Proxied (orange cloud).

### 2. Prepare the server

On the VPS (after this repo's changes are on `main`):

```bash
curl -fsSLO https://raw.githubusercontent.com/abdhamed22/Abdulhamed-Hamed/main/deploy/server-setup.sh
less server-setup.sh          # read it first
sudo bash server-setup.sh
```

If the repo is private, `curl` gets a 404. In that case, create the file with `nano server-setup.sh` and paste the script's contents from GitHub instead.

The script is built to sit next to existing services:

- It stops before changing anything if `apache2ctl configtest` already fails, if port 80 isn't served by Apache, or if another vhost already uses `cv.u-network-it.com`.
- It only adds one new vhost, `zz-cv.u-network-it.com.conf`. The `zz-` prefix makes it load last, so it never becomes Apache's default site.
- It validates the config again before a **graceful** reload. If Apache rejects it, the new vhost is removed and Apache is not reloaded.
- For HTTPS on 443 it reuses an existing certificate that covers the subdomain (for example a Cloudflare Origin wildcard cert), or falls back to a self-signed one.

At the end it prints the values for the GitHub secrets.

### 3. Add GitHub secrets

In the repo, go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
| --- | --- |
| `SSH_HOST` | Server **IP address** (not the Cloudflare domain, since Cloudflare doesn't proxy SSH) |
| `SSH_PORT` | SSH port (the script prints it) |
| `SSH_USER` | `cvdeploy` |
| `SSH_KNOWN_HOSTS` | The `cv-server ssh-ed25519 ...` line the script prints |
| `SSH_PRIVATE_KEY` | The private key the script prints, including the BEGIN/END lines |

### 4. Deploy

Go to **Actions → Validate & deploy CV site → Run workflow**, or push to `main`.

## Notes

- **Firewall:** the GitHub Actions runners must be able to reach SSH on the server. If the Vultr firewall or `ufw` only allows SSH from your own IP, deploys will time out.
- **Cloudflare SSL/TLS mode:**
  - **Full**: works with any certificate the script picks.
  - **Full (strict)**: needs a trusted cert. Create a Cloudflare Origin Certificate (SSL/TLS → Origin Server), save it on the server, then re-run:
    `sudo SSL_CERT=/path/cert.pem SSL_KEY=/path/key.pem bash server-setup.sh`
  - **Flexible**: uses port 80 only.
- **New deploy key:** `sudo ROTATE_KEY=1 bash server-setup.sh`, then update the `SSH_PRIVATE_KEY` secret.
- **Remove everything:**
  ```bash
  sudo a2dissite zz-cv.u-network-it.com && sudo systemctl reload apache2
  sudo rm /etc/apache2/sites-available/zz-cv.u-network-it.com.conf
  sudo userdel -r cvdeploy && sudo rm -rf /var/www/cv.u-network-it.com
  ```

## Preview locally

```bash
cd site
python3 -m http.server 8000
# open http://localhost:8000
```

## Updating the content

- **Text** (projects, experience, certifications): edit `site/index.html`. Each section is marked with a comment like `<!-- ============ PROJECTS ============ -->`.
- **CV PDF**: replace `site/assets/Abdulhameed_Hameed_CV.pdf`, keeping the same file name.
- **Photo**: replace `site/assets/img/profile.jpg` and `profile.webp` with square images.
- **Colors**: the tokens at the top of `site/assets/css/style.css`; `--hl` is the yellow highlighter accent.

Every push to `main` redeploys the site automatically.
