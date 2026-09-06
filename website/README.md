# XM5 Control landing page

React + Vite + Tailwind CSS landing page for XM5 Control.

Live site: https://xm5-control-macos.vercel.app

## Local development

From the repository root:

```sh
cd website
pnpm install --frozen-lockfile
pnpm run dev
```

The development server defaults to port 8443. Run `pnpm run build` to generate `dist/`, or `pnpm run preview` to preview the production build.

## Editing

- `src/App.tsx`: landing-page content, layout, and download links.
- `src/index.css`: global styles.
- `.figma/make/site.json`: page title, description, and favicon configuration used by the Vite plugin.
- `public/favicon.svg`: headphones favicon.

## Vercel

The existing Vercel project is named `xm5-control-macos`.
If connecting this repository for automatic deployments, configure:

- Root Directory: `website`
- Framework Preset: Vite
- Install Command: `pnpm install --frozen-lockfile`
- Build Command: `pnpm run build`
- Output Directory: `dist`

The GitHub repository connection is separate from the existing CLI deployment. Do not create a second Vercel project just to connect the repository.

Dependencies, generated build files, environment files, and local Vercel project state are excluded from version control.
