// Astro blog SSR - converted to NANO format
// Tests content rendering + dynamic routes

// Simulated content collection (what Astro generates)
const posts = [
  {
    slug: 'hello-world',
    title: 'Hello World',
    date: '2024-01-15',
    content: '<p>This is my first post on NANO!</p>'
  },
  {
    slug: 'astro-on-nano',
    title: 'Running Astro on NANO',
    date: '2024-01-20',
    content: '<p>Astro SSR works great on the NANO runtime.</p><p>Here is why...</p>'
  }
];

// Layout component (simplified)
function layout(title, content) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${title} | NANO Blog</title>
  <style>
    body { font-family: system-ui; max-width: 800px; margin: 0 auto; padding: 2rem; }
    article { margin: 2rem 0; padding: 1rem; border-bottom: 1px solid #eee; }
    a { color: #0066cc; }
  </style>
</head>
<body>
  <nav><a href="/">Home</a></nav>
  <main>${content}</main>
  <footer><p>Rendered by NANO at ${new Date().toISOString()}</p></footer>
</body>
</html>`;
}

// Index page - list all posts
function renderIndex() {
  const postList = posts.map(p => `
    <article>
      <h2><a href="/posts/${p.slug}">${p.title}</a></h2>
      <time>${p.date}</time>
    </article>
  `).join('');

  return layout('Home', `<h1>Blog Posts</h1>${postList}`);
}

// Post page - dynamic route
function renderPost(slug) {
  const post = posts.find(p => p.slug === slug);
  if (!post) return null;

  return layout(post.title, `
    <article>
      <h1>${post.title}</h1>
      <time>${post.date}</time>
      ${post.content}
    </article>
    <a href="/">← Back to posts</a>
  `);
}

// RSS feed - tests XML response
function renderRSS() {
  const items = posts.map(p => `
    <item>
      <title>${p.title}</title>
      <link>https://example.com/posts/${p.slug}</link>
      <pubDate>${new Date(p.date).toUTCString()}</pubDate>
    </item>
  `).join('');

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>NANO Blog</title>
    <link>https://example.com</link>
    ${items}
  </channel>
</rss>`;
}

// NANO entry point
export default {
  fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname();

    // Static routes
    if (path === '/' || path === '/index.html') {
      return new Response(renderIndex(), {
        headers: { 'Content-Type': 'text/html; charset=utf-8' }
      });
    }

    if (path === '/rss.xml') {
      return new Response(renderRSS(), {
        headers: { 'Content-Type': 'application/xml; charset=utf-8' }
      });
    }

    // Dynamic route: /posts/:slug
    if (path.startsWith('/posts/')) {
      const slug = path.slice(7); // Remove '/posts/'
      const html = renderPost(slug);
      if (html) {
        return new Response(html, {
          headers: { 'Content-Type': 'text/html; charset=utf-8' }
        });
      }
    }

    return new Response('Not Found', { status: 404 });
  }
});
