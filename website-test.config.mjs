import { readFileSync, readdirSync } from 'node:fs';

const languages = Object.keys(JSON.parse(readFileSync(new URL('./website/content.json', import.meta.url), 'utf8')));
export default {
  ...{
  "prefix": "/LumaView/",
  "url": "https://ixiehao.github.io/LumaView/",
  "directory": "website",
  "build": null,
  "breakpoints": [
    720,
    900
  ],
  "cards": ".feature",
  "uniform": [],
  "picker": "#language-switch",
  "menu": ".language-options",
  "languageAttribute": "data-language"
},
  grids: [{"selector": ".hero", "columns": [[720, 1], [10000, 2]]}],
  scriptsDirectory: 'Scripts',
  languages
};
