import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://www.theweekend.org.uk',
  output: 'static',
  trailingSlash: 'never',
  build: {
    format: 'directory'
  }
});
