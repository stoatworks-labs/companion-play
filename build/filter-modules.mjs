// Enforce the module licence policy on the extracted offline bundle.
//
// companion-play ships a bootable image, so every module in it is redistributed
// by us, not merely downloaded by the operator from Bitfocus. That is a
// different obligation, and it is why this file exists: an image may only carry
// modules under licences on the allow-list, and what shipped must be written
// down.
//
// Run with the *target's* bundled Node inside the chroot, so there is no second
// runtime to install on the build host.
//
//   node filter-modules.mjs <moduleDir> <allowList,comma,separated> <reportPath>
//
// Exits non-zero if a module declares no licence at all. That is deliberate:
// "undeclared" is not the same as "permissive", and silently shipping it would
// be the one outcome this check exists to prevent.

import { readdirSync, readFileSync, existsSync, statSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const [, , moduleDir, allowRaw, reportPath] = process.argv
if (!moduleDir || !allowRaw || !reportPath) {
	console.error('usage: filter-modules.mjs <moduleDir> <allowList> <reportPath>')
	process.exit(2)
}

const allow = new Set(
	allowRaw
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean)
)

/** Read a module's declared licence. Companion's own manifest wins; package.json is the fallback. */
function licenceOf(dir) {
	for (const [file, pick] of [
		[join(dir, 'companion', 'manifest.json'), (m) => m.license],
		[join(dir, 'package.json'), (m) => (typeof m.license === 'string' ? m.license : null)],
	]) {
		if (!existsSync(file)) continue
		try {
			const parsed = JSON.parse(readFileSync(file, 'utf8'))
			const lic = pick(parsed)
			if (lic) return { licence: lic, manifest: parsed }
		} catch {
			// A module with unparseable metadata is treated as undeclared below,
			// which fails the build rather than shipping something unknown.
		}
	}
	return { licence: null, manifest: null }
}

const kept = []
const removed = []
const undeclared = []

for (const name of readdirSync(moduleDir)) {
	const dir = join(moduleDir, name)
	if (!statSync(dir).isDirectory()) continue

	const { licence, manifest } = licenceOf(dir)
	const row = {
		dir: name,
		id: manifest?.id ?? name,
		name: manifest?.name ?? manifest?.shortname ?? name,
		version: manifest?.version ?? '',
		licence: licence ?? 'UNDECLARED',
	}

	if (!licence) {
		undeclared.push(row)
		continue
	}
	if (allow.has(licence)) {
		kept.push(row)
	} else {
		removed.push(row)
		rmSync(dir, { recursive: true, force: true })
	}
}

const sortByDir = (a, b) => a.dir.localeCompare(b.dir)
kept.sort(sortByDir)
removed.sort(sortByDir)

const lines = [
	'# Modules shipped in this companion-play image, and their declared licences.',
	'#',
	'# Only licences on the allow-list are redistributed in the image. Anything',
	'# else is removed at build time and listed at the bottom; install those',
	'# yourself from an offline bundle downloaded from your own Companion.',
	'#',
	`# allow-list: ${[...allow].join(', ')}`,
	'#',
	'# dir\tid\tversion\tlicence',
	...kept.map((r) => `${r.dir}\t${r.id}\t${r.version}\t${r.licence}`),
	'#',
	'# REMOVED (licence not on the allow-list):',
	...removed.map((r) => `# ${r.dir}\t${r.id}\t${r.version}\t${r.licence}`),
	'',
]
writeFileSync(reportPath, lines.join('\n'))

const hist = {}
for (const r of kept) hist[r.licence] = (hist[r.licence] ?? 0) + 1

console.log(`kept    ${kept.length}`)
for (const [lic, n] of Object.entries(hist).sort((a, b) => b[1] - a[1])) {
	console.log(`          ${String(n).padStart(4)}  ${lic}`)
}
console.log(`removed ${removed.length}`)
for (const r of removed) console.log(`          ${r.dir} (${r.licence})`)

if (undeclared.length) {
	console.error(`\nxxx ${undeclared.length} module(s) declare no licence at all:`)
	for (const r of undeclared) console.error(`      ${r.dir}`)
	console.error('    Refusing to build. An undeclared licence is not a permissive one;')
	console.error('    add it to the allow-list only after establishing what it actually is.')
	process.exit(1)
}
