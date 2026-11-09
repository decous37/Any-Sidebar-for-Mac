import {spawnSync} from 'node:child_process';
const result=spawnSync(process.execPath,['node_modules/vite/bin/vite.js','build','--config','vite.macos.config.ts'],{stdio:'inherit'});
process.exit(result.status??1);
