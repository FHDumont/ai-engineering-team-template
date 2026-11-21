#!/usr/bin/env python3
"""measure-session.py: session measurements from a Claude Code JSONL transcript.

Usage: measure-session.py <transcript.jsonl> [...] [--json]

Counts, per file: owner messages (touches), tool calls, words read in tool
results (an approximation of what the AI read), input/output tokens when the
transcript has `usage`, and choice questions (AskUserQuestion). Triage
accuracy and time to merge come from GitHub and are not measured here.
"""

import json
import sys


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(text_of(c.get("text") or c.get("content") or "") if isinstance(c, dict) else str(c)
                        for c in content)
    return ""


def measure(path):
    m = {"file": path, "user_messages": 0, "tool_calls": 0, "choice_questions": 0,
         "words_read": 0, "input_tokens": 0, "output_tokens": 0}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            msg = rec.get("message") or {}
            role = msg.get("role") or rec.get("type")
            content = msg.get("content")
            usage = msg.get("usage") or {}
            m["input_tokens"] += usage.get("input_tokens", 0) or 0
            m["output_tokens"] += usage.get("output_tokens", 0) or 0
            items = content if isinstance(content, list) else []
            if role == "user":
                results = [c for c in items if isinstance(c, dict) and c.get("type") == "tool_result"]
                if results:
                    for r in results:
                        m["words_read"] += len(text_of(r.get("content")).split())
                elif text_of(content).strip():
                    m["user_messages"] += 1
            elif role == "assistant":
                for c in items:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        m["tool_calls"] += 1
                        if c.get("name") == "AskUserQuestion":
                            m["choice_questions"] += 1
    return m


def main(argv):
    args = [a for a in argv[1:] if a != "--json"]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if args else 2
    rows = [measure(p) for p in args]
    if "--json" in argv:
        print(json.dumps(rows, ensure_ascii=False))
    else:
        for r in rows:
            print("%(file)s: user_messages=%(user_messages)d tool_calls=%(tool_calls)d "
                  "choice_questions=%(choice_questions)d words_read=%(words_read)d "
                  "tokens_in=%(input_tokens)d tokens_out=%(output_tokens)d" % r)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
