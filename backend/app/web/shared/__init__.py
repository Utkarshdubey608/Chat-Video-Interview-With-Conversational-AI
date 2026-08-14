"""Port of `web_version/talbotiq-platform/shared/*.ts`.

That directory is imported by BOTH the Express server and the React frontend, and
not only for types:

    shared/inviteEmail.ts  -> invite_email.py   (5 server consumers)
    shared/speech.ts       -> speech.py         (voice.ts, tavusServer.ts)
    shared/autopilot.ts    -> types only, fold into web/schemas.py

**Rendering parity is a real risk here.** `inviteEmailRender.ts` exists so that
"the sent email is byte-identical to the client preview" — today the frontend and
the server run the same TypeScript. Once the server side is Python, nothing
enforces that, and the preview a recruiter approves can silently drift from what
the candidate receives.

So this port ships with a shared fixture set: input/expected-output pairs in a
JSON file that BOTH the TypeScript and the Python test suites read and assert
against. That file is the contract — neither implementation changes without it.
"""
