# Abdulhameed Hameed: CV website

Personal CV site for **Abdulhameed Hameed**, Network & Systems Engineer growing into Cloud & DevOps.

**Live site:** https://abdhamed22.github.io/Abdulhamed-Hamed/ (available after the first deploy, see below)

It's a plain static site (HTML, CSS and a little JavaScript) with no build step. It includes light and dark themes, a mobile layout, and a downloadable PDF CV.

## Structure

```
site/
├── index.html                    # all page content lives here
└── assets/
    ├── css/style.css             # theme colors are variables at the top
    ├── js/main.js                # theme toggle, mobile menu, terminal animation
    ├── img/profile.jpg|.webp     # profile photo (720x720)
    ├── img/favicon.svg
    └── Abdulhameed_Hameed_CV.pdf # the "Download CV" file
.github/workflows/deploy.yml      # CI/CD: validate, then deploy to GitHub Pages
```

## Preview locally

```bash
cd site
python3 -m http.server 8000
# open http://localhost:8000
```

## Deploying (one-time setup)

1. Merge this work into `main`.
2. On GitHub, open **Settings → Pages** and set **Source** to **GitHub Actions**.
3. Every push to `main` then runs the pipeline:
   - **validate**: runs `html-validate` and checks that every local file the page references exists
   - **deploy**: publishes the `site/` folder to GitHub Pages

Pull requests run only the validate job.

## Updating the content

- **Text** (projects, experience, certifications): edit `site/index.html`. Each section is marked with a comment like `<!-- ============ PROJECTS ============ -->`.
- **CV PDF**: replace `site/assets/Abdulhameed_Hameed_CV.pdf`, keeping the same file name.
- **Photo**: replace `site/assets/img/profile.jpg` and `profile.webp` with square images.
- **Colors**: change the `--accent` values at the top of `site/assets/css/style.css`.
