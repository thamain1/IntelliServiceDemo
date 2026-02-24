const fs = require('fs');
const path = require('path');

const sqlPath = path.join(__dirname, '../project/supabase/seeds/seed_dunaway_customers.sql');
const outPath = path.join(__dirname, '../supabase/functions/import-customers/index.ts');

const sqlContent = fs.readFileSync(sqlPath, 'utf8');
const escapedSql = sqlContent.replace(/`/g, '\`').replace(/\${/g, '\\${');

const header = "import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'\n" +
"import postgres from 'https://deno.land/x/postgresjs/mod.js'\n" +
"\n" +
"const corsHeaders = {\n" +
"  'Access-Control-Allow-Origin': '*' ,\n" +
"  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',\n" +
"}\n" +
"\n" +
"serve(async (req) => {\n" +
"  try {\n" +
"    const connectionString = Deno.env.get('SUPABASE_DB_URL')\n" +
"    if (!connectionString) throw new Error('Missing SUPABASE_DB_URL')\n" +
"    \n" +
"    const sql = postgres(connectionString)\n" +
"    const rawSql = `\n";

const footer = "\n" +
"    `;\n" +
"\n" +
"    await sql.unsafe(rawSql);\n" +
"    return new Response(JSON.stringify({ msg: 'Success' }), { headers: corsHeaders })\n" +
"  } catch (err) {\n" +
"    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: corsHeaders })\n" +
"  }\n" +
"})\n";

fs.writeFileSync(outPath, header);
fs.appendFileSync(outPath, escapedSql);
fs.appendFileSync(outPath, footer);
console.log('Done.');