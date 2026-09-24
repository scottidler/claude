/**
 * rules - inline Scott's always-on rules into the pi system prompt.
 *
 * Claude Code auto-loads `~/repos/.claude/rules/` and resolves `@file` includes in
 * CLAUDE.md. pi does neither: context files are loaded verbatim with no include
 * directive. So this extension does the job Claude Code's loader does, reading the same
 * shared rules directory so the two harnesses never drift.
 *
 * Always-on rules are inlined in full. Path-scoped rules are listed by name and glob so
 * the agent reads them when it touches a matching file. `~/.claude/WHOAMI.md` and
 * `~/.claude/tools.md` are inlined too, since CLAUDE.md pulls them in with `@` lines that
 * pi would otherwise render as literal text.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RULES_DIR = path.join(os.homedir(), "repos", ".claude", "rules");
const INLINE_FILES = [
	path.join(os.homedir(), ".claude", "WHOAMI.md"),
	path.join(os.homedir(), ".claude", "tools.md"),
];

/**
 * voice.md ships empty frontmatter but CLAUDE.md declares it always-on, and the rules
 * directory is shared with Claude Code so its frontmatter is not ours to change.
 */
const ALWAYS_ON_EXTRAS = new Set(["voice"]);

/** interaction.md is already carried by APPEND_SYSTEM.md; inlining it again would duplicate it. */
const SKIP = new Set(["interaction"]);

type Rule = {
	name: string;
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

function parseRule(name: string, text: string): Rule {
	const { fm, body } = splitFrontmatter(text);
	const globs = [...fm.matchAll(/^\s*-\s*"?([^"\n]+?)"?\s*$/gm)].map((m) => m[1]);
	const alwaysOn =
		/^\s*alwaysApply:\s*true\s*$/m.test(fm) ||
		globs.includes("**/*") ||
		ALWAYS_ON_EXTRAS.has(name);
	return { name, body: body.trim(), alwaysOn, globs };
}

function loadRules(): Rule[] {
	if (!fs.existsSync(RULES_DIR)) return [];
	return fs
		.readdirSync(RULES_DIR)
		.filter((f) => f.endsWith(".md"))
		.map((f) => f.slice(0, -3))
		.filter((name) => !SKIP.has(name))
		.sort()
		.map((name) => {
			const file = path.join(RULES_DIR, `${name}.md`);
			return parseRule(name, fs.readFileSync(file, "utf8"));
		});
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
			sections.push(`### rules/${r.name}.md\n\n${r.body}`);
		}

		const scoped = rules.filter((x) => !x.alwaysOn);
		if (scoped.length > 0) {
			const list = scoped
				.map((r) => `- \`${RULES_DIR}/${r.name}.md\` applies to ${r.globs.join(", ")}`)
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
