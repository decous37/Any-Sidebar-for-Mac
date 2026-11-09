import ts from 'typescript-eslint';
export default ts.config({ignores:['dist/**','node_modules/**','artifacts/**','release/**']},...ts.configs.recommended,{files:['**/*.{ts,tsx,js,mjs}'],rules:{'@typescript-eslint/no-unused-vars':['error',{argsIgnorePattern:'^_'}],'@typescript-eslint/no-explicit-any':'error'}});
