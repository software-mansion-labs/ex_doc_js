import fs from 'node:fs/promises'
import { Application } from 'typedoc'

const request = JSON.parse(await fs.readFile(process.argv[2], 'utf8'))
const options = { entryPoints: request.entryPoints }

if (request.name) options.name = request.name
if (request.tsconfig) options.tsconfig = request.tsconfig

const app = await Application.bootstrapWithPlugins(options)
const project = await app.convert()

if (!project) process.exit(1)

await app.generateJson(project, request.output)
