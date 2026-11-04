import { appendFileSync } from 'node:fs';
import site from '../website-test.config.mjs';
if (!site.languages.includes('en') || new Set(site.languages).size !== site.languages.length || site.languages.some(id => !/^[a-z]{2}$/.test(id))) throw Error('Invalid website language list');
const json = JSON.stringify(site.languages);
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `languages=${json}\n`);
else console.log(json);
