// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import mermaid from 'astro-mermaid';
import mdx from '@astrojs/mdx';

// https://astro.build/config
export default defineConfig({
	integrations: [
		mermaid({
			theme: 'neutral',
			autoTheme: true,
		}),
		starlight({
			title: 'structured_log',
			description:
				'Self-hosted, multi-tenant structured logging: a Dart logging core, Flutter in-app viewers, an HTTP sender, and a log-collection server with an admin client.',
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/pese-git/structured_log',
				},
			],
			locales: {
				root: { label: 'English', lang: 'en' },
				ru: { label: 'Русский', lang: 'ru' },
			},
			sidebar: [
				{ label: 'Overview', translations: { ru: 'Обзор' }, link: '/overview/' },
				{
					label: 'Guides',
					translations: { ru: 'Руководства' },
					items: [{ autogenerate: { directory: 'guides' } }],
				},
				{
					label: 'Architecture',
					translations: { ru: 'Архитектура' },
					items: [{ autogenerate: { directory: 'architecture' } }],
				},
				{
					label: 'API Reference',
					translations: { ru: 'API' },
					items: [{ autogenerate: { directory: 'api' } }],
				},
				{
					label: 'Operations',
					translations: { ru: 'Эксплуатация' },
					items: [{ autogenerate: { directory: 'operations' } }],
				},
			],
			customCss: ['./src/styles/custom.css'],
			head: [
				{
					tag: 'link',
					attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
				},
				{
					tag: 'link',
					attrs: {
						rel: 'preconnect',
						href: 'https://fonts.gstatic.com',
						crossorigin: true,
					},
				},
				{
					tag: 'link',
					attrs: {
						rel: 'stylesheet',
						href: 'https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap',
					},
				},
			],
		}),
		mdx(),
	],
});
