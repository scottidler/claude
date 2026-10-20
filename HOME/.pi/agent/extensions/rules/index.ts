/**
 * rules - inline Scott's always-on rules into the pi system prompt.
 *
 * Claude Code auto-loads `~/repos/.claude/rules/` and resolves `@file` includes in
 * CLAUDE.md. pi does neither: context files are loaded verbatim with no include
 * directive. So this extension does the job Claude Code's loader does, reading the same
 * shared rules directory so the two harnesses never drift.
 *
 * Always-on rules are inlined in full. Path-scoped rules are listed by name and glob so
 * the agent reads them when it touches a matching file. `~/.claude/WHOAMI.md` is
 * inlined too, since CLAUDE.md pulls it in with an `@` line that pi would otherwise
 * render as literal text.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RULES_DIR = path.join(os.homedir(), "repos", ".claude", "rules");
/**
 * Rules Claude Code injects on a trigger (the rails rule router). pi has no router,
 * so it inlines every one of them always-on, as it did before they moved out of rules/.
 */
const ROUTED_DIR = path.join(os.homedir(), "repos", ".claude", "routed");
const INLINE_FILES = [
	path.join(os.homedir(), ".claude", "WHOAMI.md"),
];

/** interaction.md is already carried by APPEND_SYSTEM.md; inlining it again would duplicate it. */
const SKIP = new Set(["interaction"]);

type Rule = {
	name: string;
	/** `rules` or `routed`, the directory it came from. */
	dir: string;
	body: string;
	alwaysOn: boolean;
	globs: string[];
};

function splitFrontmatter(text: string): { fm: string; body: string } {
	if (!text.startsWith("---\n")) return { fm: "", body: text };
	const end = text.indexOf("\n---\n", 4);
	if (end === -1) return { fm: "", body: text };
	return { fm: text.slice(4, end), body: text.slice(end + 5) };
}

function parseRule(name: string, dir: string, text: string, forceOn: boolean): Rule {
	const { fm, body } = splitFrontmatter(text);
	const globs = [...fm.matchAll(/^\s*-\s*"?([^"\n]+?)"?\s*$/gm)].map((m) => m[1]);
	const alwaysOn =
		forceOn ||
		/^\s*alwaysApply:\s*true\s*$/m.test(fm) ||
		globs.includes("**/*");
	return { name, dir, body: body.trim(), alwaysOn, globs };
}

function loadDir(dir: string, forceOn: boolean): Rule[] {
	if (!fs.existsSync(dir)) return [];
	return fs
		.readdirSync(dir)
		.filter((f) => f.endsWith(".md"))
		.map((f) => f.slice(0, -3))
		.filter((name) => !SKIP.has(name))
		.sort()
		.map((name) => {
			const file = path.join(dir, `${name}.md`);
			return parseRule(name, path.basename(dir), fs.readFileSync(file, "utf8"), forceOn);
		});
}

function loadRules(): Rule[] {
	return [...loadDir(RULES_DIR, false), ...loadDir(ROUTED_DIR, true)];
}

function readInlineFile(file: string): { name: string; body: string } | undefined {
	try {
		return { name: path.basename(file), body: fs.readFileSync(file, "utf8").trim() };
	} catch {
		return undefined;
	}
}

export default function rulesExtension(pi: ExtensionAPI) {
	let rules: Rule[] = [];
	let inlined: { name: string; body: string }[] = [];

	pi.on("session_start", async (_event, ctx) => {
		rules = loadRules();
		inlined = INLINE_FILES.map(readInlineFile).filter((x) => x !== undefined);

		const on = rules.filter((r) => r.alwaysOn).length;
		const scoped = rules.length - on;
		if (rules.length > 0) {
			ctx.ui.notify(`rules: ${on} always-on, ${scoped} path-scoped`, "info");
		} else {
			ctx.ui.notify(`rules: none found at ${RULES_DIR}`, "warning");
		}
	});

	pi.on("before_agent_start", async (event) => {
		if (rules.length === 0 && inlined.length === 0) return;

		const sections: string[] = [];

		for (const f of inlined) {
			sections.push(`### ${f.name}\n\n${f.body}`);
		}

		for (const r of rules.filter((x) => x.alwaysOn)) {
			sections.push(`### ${r.dir}/${r.name}.md\n\n${r.body}`);
		}

		const scoped = rules.filter((x) => !x.alwaysOn);
		if (scoped.length > 0) {
			const list = scoped
				.map((r) => `- \`${path.join(path.dirname(RULES_DIR), r.dir)}/${r.name}.md\` applies to ${r.globs.join(", ")}`)
				.join("\n");
			sections.push(
				`### Path-scoped rules\n\nRead the matching file before writing code that matches its globs:\n\n${list}`,
			);
		}

		return {
			systemPrompt: `${event.systemPrompt}\n\n## Scott's rules\n\nThese are binding. They are the same files Claude Code loads, at \`${RULES_DIR}\`.\n\n${sections.join("\n\n")}\n`,
		};
	});
}
