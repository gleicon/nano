// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'NANO Documentation',
			description: 'JavaScript runtime for serverless workloads',
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/gleicon/nano' },
			],
			sidebar: [
				{
					label: 'Getting Started',
					autogenerate: { directory: 'getting-started' },
				},
				{
					label: 'Configuration',
					autogenerate: { directory: 'config' },
				},
				{
					label: 'API Reference',
					autogenerate: { directory: 'api' },
				},
				{
					label: 'WinterCG Compliance',
					autogenerate: { directory: 'wintercg' },
				},
				{
					label: 'Deployment',
					autogenerate: { directory: 'deployment' },
				},
			],
			editLink: {
				baseUrl: 'https://github.com/gleicon/nano/edit/main/docs/',
			},
			lastUpdated: true,
			pagination: true,
			customCss: [
				// Custom CSS can be added here if needed
			],
		}),
	],
});
