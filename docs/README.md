# NANO Documentation

Built with [Astro](https://astro.build) + [Starlight](https://starlight.astro.build).

## Project Structure

```
docs/
├── public/              # Static assets (favicons, images)
├── src/
│   └── content/docs/    # Documentation pages (.md)
│       ├── getting-started/
│       ├── config/
│       ├── api/
│       ├── wintercg/
│       └── deployment/
├── astro.config.mjs     # Site configuration
├── package.json
└── tsconfig.json
```

Each `.md` file in `src/content/docs/` becomes a page. Sidebar order is controlled via frontmatter `sidebar.order`.

## Development

```bash
cd docs
npm install
npm run dev
```

Open http://localhost:4321 to preview.

## Building for Production

```bash
npm run build
```

Static output goes to `docs/dist/`. Serve it with any static file server, reverse proxy, or deploy to GitHub Pages / Netlify / Vercel.

## Serving with NANO

You can use NANO itself to serve the documentation site. Create a wrapper app:

**docs-app/index.js:**

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    return new Response(`Documentation site — serve dist/ with a static server`, {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

For production, build the static site and serve `dist/` behind Nginx or Caddy. See the [Deployment guide](src/content/docs/deployment/index.md).

## Commands

| Command           | Action                                      |
| ----------------- | ------------------------------------------- |
| `npm install`     | Install dependencies                        |
| `npm run dev`     | Start dev server at `localhost:4321`        |
| `npm run build`   | Build static site to `./dist/`              |
| `npm run preview` | Preview build locally before deploying      |

## Deploying

### GitHub Pages

```bash
npm run build
# Copy dist/ contents to your gh-pages branch
```

### Nginx

```nginx
server {
    listen 80;
    server_name docs.example.com;
    root /var/www/nano-docs/dist;
    index index.html;

    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}
```

### Caddy

```
docs.example.com {
    root * /var/www/nano-docs/dist
    file_server
    try_files {path} {path}/ {path}.html
}
```
