import { validateAppcast } from './lib/appcast.mjs';
import { installer } from './lib/installer.mjs';

const machineHeaders = {
  'X-Content-Type-Options': 'nosniff',
};

function unavailableAppcast() {
  return new Response('Appcast unavailable.\n', {
    status: 503,
    headers: {
      ...machineHeaders,
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

async function appcastResponse(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed.\n', {
      status: 405,
      headers: {
        ...machineHeaders,
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
        Allow: 'GET, HEAD',
      },
    });
  }
  try {
    const assetURL = new URL(request.url);
    assetURL.search = '';
    assetURL.hash = '';
    const asset = await env.ASSETS.fetch(new Request(assetURL, { method: 'GET' }));
    const contentType = asset.headers.get('Content-Type') || '';
    if (!asset.ok || !/^(?:application|text)\/(?:xml|rss\+xml)\b/i.test(contentType)) return unavailableAppcast();
    const bytes = new Uint8Array(await asset.arrayBuffer());
    validateAppcast(bytes);
    return new Response(request.method === 'HEAD' ? null : bytes, {
      headers: {
        ...machineHeaders,
        'Content-Type': 'application/xml; charset=utf-8',
        'Cache-Control': 'public, max-age=300, must-revalidate',
      },
    });
  } catch {
    return unavailableAppcast();
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/appcast.xml') return appcastResponse(request, env);
    if (url.pathname === '/install') {
      return new Response(installer, {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'no-store',
        },
      });
    }
    return env.ASSETS.fetch(request);
  },
};
