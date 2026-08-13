# Mimic by TalbotIQ — User Manual

**AI interviews for every candidate.**

---

### About this manual

This manual explains how to use Mimic, the AI interview platform built by TalbotIQ. It is written for the people who use the product every day — recruiters, hiring managers and candidates — not for developers.

**How to use it**

- If you are a **recruiter** setting up your first interview, start at [2. Getting Started](#2-getting-started), then read [4.2 Interview templates](#42-interview-templates) onwards.
- If you are a **candidate** who received an invitation, read [2.5 First-time setup — candidates](#25-first-time-setup--candidates) and [4.13 Taking an interview](#413-taking-an-interview-candidates).
- If something has gone wrong, jump straight to [8. Troubleshooting](#8-troubleshooting), which lists every message the product can show you.

**A note on unverified items**

Where the product's behaviour could not be confirmed with certainty, this manual says **[NEEDS INPUT]** and explains what still needs answering. Those passages are deliberately not filled in with guesses. Please treat them as open items for the product team rather than as instructions.

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Getting Started](#2-getting-started)
3. [Interface Overview](#3-interface-overview)
4. [Core Features](#4-core-features)
5. [Settings & Configuration](#5-settings--configuration)
6. [Roles & Permissions](#6-roles--permissions)
7. [Notifications, Exports & Integrations](#7-notifications-exports--integrations)
8. [Troubleshooting](#8-troubleshooting)
9. [FAQ](#9-faq)
10. [Glossary](#10-glossary)
11. [Appendix](#11-appendix)
12. [Coverage checklist](#12-coverage-checklist)

---

# 1. Introduction

## 1.1 What Mimic is

Mimic is an **AI interview platform**. It conducts the first round of your hiring process for you.

Instead of a recruiter phoning every applicant, Mimic invites each candidate by email, interviews them at whatever time suits them, and scores their answers against a scoring guide that you define. Your team then reviews a ranked shortlist with the evidence attached, rather than working through a queue of applications.

Two names appear in the product, and they mean different things:

| Name | What it refers to |
|---|---|
| **Mimic** | The product — the interviewing platform itself. This is the name shown in the top-left of the app. |
| **TalbotIQ** | The company that builds Mimic. It is also the default company name used on candidate-facing screens and emails until you change it. |

## 1.2 Who it is for

Mimic recognises four kinds of people.

| Person | What they do |
|---|---|
| **Recruiter** | Sets up interviews, invites candidates, reviews scored reports and analytics, and manages settings. This is the main user of the product. |
| **Candidate** | Receives an invitation, takes the interview, and sees a confirmation screen when they are finished. Candidates never see their own scores. |
| **Administrator** | A recruiter who has been given extra visibility. This is not a separate account type — it is an extra permission added to a recruiter account by your systems administrator. |
| **Website visitor** | Anyone browsing the public Mimic website before signing in. They can read the marketing pages and request a demo. |

## 1.3 The six interview formats

Mimic can interview a candidate in six different ways. Each one is called a **track**. Every track scores against the same scoring guide, so results from different tracks can be compared directly.

| Track | What the candidate experiences | Best suited to |
|---|---|---|
| **Timed Q&A** | One question at a time, with a countdown. A short preparation period, then a timed window to type an answer. The answer submits automatically when time runs out. | Roles where performance under time pressure matters |
| **Chatbot** (also called *Conversational*) | A typed back-and-forth conversation, like messaging. The interviewer can ask follow-up questions based on what the candidate says. | Fast, mobile-friendly screening at volume |
| **Voice** | A live spoken conversation with an AI interviewer. The candidate talks; the AI listens and replies out loud. | Roles where communication is the job |
| **Video Avatar** | An on-screen AI presenter asks each question aloud on video and reacts to the answers. | A face-to-face round without scheduling |
| **Video Interview** | The candidate answers on camera. What they say is transcribed live and becomes their answer. | When you want to see and hear the candidate |
| **Two-way Interview** | A live video call between a real recruiter and the candidate. Mimic records it, transcribes it, and scores it afterwards. | Later rounds and panel interviews |

> **Note on availability.** In the template editor, only Timed Q&A, Chatbot, Voice and Video Avatar can be chosen. Video Interview and Two-way Interview are selected when you invite candidates rather than on a template. Video Avatar is currently labelled "scaffold" in the template editor and "Preview" on the candidate's format-selection screen. **[NEEDS INPUT]** — please confirm whether Video Interview and Two-way Interview are intended to be invitation-only, and what "Preview" status means for customers using Video Avatar.

## 1.4 Key benefits

- **Every applicant gets interviewed.** Volume stops being a staffing problem — interviews run around the clock without anyone scheduling them.
- **Every candidate is measured the same way.** One scoring guide is applied identically to everyone applying for a role, so scores compare directly.
- **Scores come with their evidence.** Each report links its scores back to the candidate's actual answers and a transcript, so a reviewer can check the reasoning.
- **A person always decides.** Mimic produces a recommendation. Advancing, rejecting and overriding are all actions a recruiter takes, and each one is recorded.
- **Candidates interview on their own schedule.** No calendar coordination for the first round; most tracks work on a phone.

## 1.5 What Mimic does not do

- Mimic does not automatically reject anyone. Rejection is always something a person does.
- Candidates never see their scores, their report, or any other candidate's information.
- Mimic does not replace your applicant tracking system. Candidates are brought in from a spreadsheet, an export, or a shareable link.

---

# 2. Getting Started

## 2.1 What you need

### For recruiters

| Requirement | Details |
|---|---|
| **A modern web browser** | Chrome, Edge, Firefox or Safari, kept up to date |
| **An internet connection** | A stable connection; the product is entirely web-based |
| **An account** | Created by you on the sign-in page (see [2.3](#23-creating-your-account)) |
| **Camera and microphone** | Only needed if you will run Two-way Interviews or test the Video Avatar |

### For candidates

| Requirement | Details |
|---|---|
| **A modern web browser** | On a computer, tablet or phone |
| **Your invitation email** | It contains your personal interview link |
| **An account using the invited email address** | You must sign in with the exact address the invitation was sent to |
| **Microphone** | Required for Voice, Video Avatar, Video Interview and Two-way Interview |
| **Camera** | Required for Video Avatar, Video Interview and Two-way Interview |
| **A quiet space** | Recommended for every track; required in practice for spoken formats |

You do not need to install an app. Everything runs in the browser.

## 2.2 Accessing Mimic

There is no installation step. Your organisation will give you a web address for the product.

- The **public website** lives at `/mimic` — anyone can read it without signing in.
- The **application** requires you to sign in first.

Opening the application's home address while signed out takes you to the sign-in page automatically. Once you are signed in, the same address takes you to the right home screen for your role: recruiters land on **Sessions**, candidates land on **Your interviews**.

![Screenshot: The Mimic sign-in page showing the TalbotIQ logo, the "Welcome" heading, email and password fields, and the "New here? Create an account" link](placeholder)

## 2.3 Creating your account

You choose whether you are a candidate or a recruiter when you create your account.

**To create an account:**

1. Go to the sign-in page.
2. Click **New here? Create an account** at the bottom of the panel.
3. Under **I am a**, click either **Candidate** or **Recruiter**.
4. Type your **Full name**. This is optional, but it is what colleagues and candidates will see.
5. Type your **Email**.
   - If you are a candidate, use the **exact email address your invitation was sent to**. An invitation will not open on any other address.
6. Type a **Password**. It must be at least 6 characters.
7. Click **Create candidate account** or **Create recruiter account**.

You are signed in immediately and taken to your home screen. There is no email-verification step.

> **Important.** The role you pick here determines what you can see and do. Choose carefully — see [6. Roles & Permissions](#6-roles--permissions). If you pick the wrong role, contact your administrator.

## 2.4 Signing in and out

**To sign in:**

1. Go to the sign-in page.
2. Type your **Email** and **Password**.
3. Click **Sign in**.

You are taken to Sessions (recruiters) or Your interviews (candidates). If you were trying to open a specific page before signing in, you are returned to that page instead.

**To sign out:**

- **Recruiters:** click the exit icon at the far right of the top navigation bar.
- **Candidates:** click **Sign out** in the top-right of Your interviews.

If sign-in fails, see [8.1 Sign-in and account errors](#81-sign-in-and-account-errors) for the exact message and what to do.

## 2.5 First-time setup — candidates

There is nothing to configure. Your first interview begins the moment you open your invitation.

1. Open the invitation email.
2. Click **Start your interview** (the button may be labelled differently if your recruiter customised the email).
3. If you are not signed in, create an account or sign in **using the email address the invitation was sent to**.
4. Follow the on-screen steps. See [4.13 Taking an interview](#413-taking-an-interview-candidates) for a full walkthrough of every format.

If you signed in with a different address, Mimic tells you so and offers a **Sign out & switch account** button.

## 2.6 First-time setup — recruiters

Work through these in order. You can skip anything you do not need yet.

### Step 1 — Add your AI key (strongly recommended)

Without an AI key, Mimic still works, but question generation and scoring fall back to a basic method that only measures answer length, and reports are marked as approximate.

1. Click **Settings** in the top navigation bar.
2. Find the **Gemini API Key (AI Interview)** panel.
3. Paste your key into the **API key** field. Keys begin with `AIza`.
4. Choose a model: **flash** (faster, the default) or **pro** (more thorough).
5. Click **Save key**.

The status line changes to show a masked version of the key and the selected model. If it still says *Not configured — using heuristic fallback*, the key was not saved.

![Screenshot: The Settings page Gemini API Key panel showing the status line, masked key, model toggle, and Save key button](placeholder)

### Step 2 — Add your avatar key (only if you will use Video Avatar)

1. On the **Settings** page, find the **Tavus — Avatar** panel.
2. Paste your Tavus API key into **Tavus API Key**. Click **Show** if you want to check what you typed.
3. Click **Test Tavus Connection**. A green *Connected* label and a count of available avatars confirms it worked.
4. Click **Save Settings**.

Saving here applies the key everywhere at once — your own screens and every candidate's Video Avatar interview.

### Step 3 — Configure your avatar (only if you will use Video Avatar)

1. Click **Avatar studio** in the top navigation bar.
2. Pick a **Replica** — the avatar face and voice — from the dropdown, or paste a replica ID directly.
3. Optionally set the **AI Interviewer Name** (what the avatar calls itself; the default is *Alex*), a **Custom Greeting**, and the **Conversational Context** that describes how it should behave.
4. Click **Apply to Candidate Interviews**.

A green confirmation appears: *✓ An avatar is applied to candidate interviews*. Until you do this, Video Avatar interviews cannot start.

> You do **not** set interview questions here. Questions come from the invitation you send. See [4.5 Inviting candidates](#45-inviting-candidates-in-bulk).

### Step 4 — Build your first interview

1. Create a **question set** if you want to ask fixed questions — see [4.3 Question sets](#43-question-sets).
2. Create a **template** that defines how the interview runs — see [4.2 Interview templates](#42-interview-templates).
3. Invite candidates — see [4.4 Creating a single interview](#44-creating-a-single-interview) for one person, or [4.5 Inviting candidates in bulk](#45-inviting-candidates-in-bulk) for many.

### Step 5 — Check your email sending is switched on

Invitations are sent by email. If your administrator has not finished connecting the mail service, Mimic runs in **dry-run** mode: it creates every invitation and link correctly but does not actually send the emails.

You will know because the confirmation screen after sending says *emails are in dry-run (not sent yet — add the SMTP login + verified sender to send for real)*.

If you see that, you can still copy each candidate's link and send it yourself. Ask your administrator to complete the mail setup — see [5.7 Settings your administrator controls](#57-settings-your-administrator-controls).

---

# 3. Interface Overview

This section describes every screen. Section 4 explains how to *use* them.

## 3.1 The recruiter navigation bar

The bar across the top of every recruiter screen contains:

| Element | Purpose |
|---|---|
| **Mimic** logo (left) | Returns you to Sessions |
| **Sessions** | Your home screen — all interviews and their status |
| **Templates** | Reusable interview configurations |
| **Question sets** | Reusable lists of fixed questions |
| **Pipelines** | Multi-round hiring flows |
| **Analytics** | Aggregate hiring metrics |
| **Avatar studio** | Configure the AI video avatar |
| **Settings** | API keys and platform options |
| **Live** badge | Appears while an avatar interview is running |
| **Add API Key →** | Appears when no avatar key has been saved; takes you to Settings |
| Initials circle | Your account. Hover to see your email (and *(admin)* if you have that permission) |
| Exit icon | Sign out |

Two screens are not on the navigation bar but are reachable from elsewhere: the avatar **Interview room** and the avatar **Results** dashboard. **[NEEDS INPUT]** — please confirm the intended route for recruiters to reach these two screens in day-to-day use.

![Screenshot: The recruiter navigation bar showing the Mimic wordmark, seven tabs with Sessions active, and the account circle](placeholder)

## 3.2 Public screens (no sign-in needed)

### Sign-in page

Contains the TalbotIQ logo, a **Welcome** heading, email and password fields, and a link to switch between signing in and creating an account. When creating an account it also shows the **I am a** role picker and a **Full name** field.

### Access denied

Shown when you open a page your role cannot see. Contains the heading **Access denied**, the message *You don't have permission to view this page*, and buttons: **Go to my home**, **Sign in** (if signed out) and **Sign out**.

### Mimic public website

The marketing home page. Sections, in order: hero with headline *Screening, decided.*; customer logos; outcomes; the six interview-track cards; a "How it works" process panel; a product showcase; a customer story; a trust section; resources; frequently asked questions; and a **Book a demo** form.

### Mimic content pages

Around fifty additional public pages organised into five areas — **Platform**, **Solutions**, **Trust**, **Resources** and **Company**. Each has a breadcrumb trail, an introduction, content sections, sometimes a question-and-answer block, and a **Book a demo** call to action. The **ROI calculator** page under Resources contains three interactive sliders.

If a marketing address does not exist, you see a page saying *We couldn't find that page* with **Back to home** and **Explore solutions** buttons.

> **Caution.** Statistics and compliance badges shown on the public website are described in the product's own source as illustrative sample data awaiting replacement, and several trust pages contain explicit placeholder markers. **[NEEDS INPUT]** — please confirm which figures and certifications are approved for external use before quoting them.

## 3.3 Candidate screens

### Your interviews

Your home screen as a candidate. Shows your email address and a list of every interview assigned to you. Each row shows the interview name, the role, the format, and either a **Start interview** / **Continue** button or a **Completed** badge.

If you have none, you see: *No interviews assigned — There are no interviews assigned to this account. If you were expecting one, make sure you're signed in with the email address your invite was sent to, or contact the recruiter.*

![Screenshot: The candidate "Your interviews" screen listing two assigned interviews, one with a Start interview button and one showing a Completed badge](placeholder)

### The interview screens

The interview runs as a sequence of screens. Which ones you see depends on the format your recruiter chose.

| Screen | When you see it | What is on it |
|---|---|---|
| **Choose your format** | Only when the recruiter did not fix the format | Three cards — Chat Interview, Voice Interview, Video Avatar — and a **Continue** button |
| **Welcome** | Always | Your company's branding, a welcome message, and three rules about timing, auto-submission and one-question-at-a-time |
| **Tell us about you** | When the interview needs your résumé | A **Your full name** field and a résumé upload area |
| **Quick system check** | Most formats | Three readiness reminders and a confirmation tickbox |
| **Video interview — before you begin** | Video Interview only | A consent tickbox about AI analysis |
| **Camera & microphone check** | Video Avatar and Two-way | A live camera preview and an **Enable camera & microphone** button |
| **Face framing** | Video Avatar | A camera view with an outline to position your face inside |
| **Question screen** | Timed Q&A and Video Interview | The question, a countdown ring, an answer box or camera, and the controls |
| **Chat screen** | Chatbot | A message thread and a typing box |
| **Voice screen** | Voice | An animated circle showing who is speaking, plus mute, end and captions buttons |
| **Live call screen** | Two-way | The interviewer's video, your own video, and call controls |
| **All done, thank you!** | Always, at the end | Confirmation that your answers were submitted |

![Screenshot: The candidate question screen showing the question text, a circular countdown timer, the answer box, and the "Submit & continue" button](placeholder)

## 3.4 Recruiter screens

### Sessions

Your home screen. A table of every interview you own.

| Column | Contains |
|---|---|
| **Candidate** | Name and email |
| **Template** | The template the interview was built from |
| **Track** | The interview format |
| **Status** | Created, System check, In progress, Completed or Expired |
| **Score** | The overall score, or a dash if not yet scored |
| **Actions** | **Copy link**, **Join live interview →** (Two-way only), **View report →** (completed only) |

Two buttons sit at the top: **+ Single link** (invite one person) and **Invite candidates** (the bulk wizard).

If you have no sessions: *No interview sessions yet — Create a session to generate a candidate link. Once they finish, scored results appear here.*

![Screenshot: The Sessions table with five candidates showing mixed statuses and scores, and the "+ Single link" and "Invite candidates" buttons above it](placeholder)

### Invite wizard

A five-step guided flow with a progress bar across the top: **Basics → Questions → Candidates → Invite email → Review**. A note at the top reminds you that you do not upload résumés here — each candidate uploads their own.

### Templates

A grid of cards. Each card shows the format icon, whether questions are *adaptive* or *fixed*, the template name, the role and seniority, the preparation and answer times, and how many scoring criteria are switched on. Each card has **Edit**, **Duplicate** and a delete icon.

### Template editor

A two-column screen. The left column contains the configuration sections; the right column is a **Live preview** that updates as you type.

Sections on the left, top to bottom: **Basics**, **Questions**, **Conversation** (conversational formats only), **Voice & persona** (Voice only), **Per-question timer** (conversational, not Voice), **Timing** (Timed Q&A only), **Scoring rubric**, **Branding**, **Integrity**.

The **Live preview** shows what the candidate sees, the per-question flow, the number of questions, the estimated total minutes, and a bar chart of your scoring weights.

![Screenshot: The template editor with the Basics and Questions sections on the left and the Live preview panel on the right showing question count and rubric weights](placeholder)

### Question sets

A two-pane screen. The left pane lists your sets with a question count on each, plus **Generate from résumé** and **New set** buttons. The right pane edits the selected set: its name, its questions (each with question text, an optional category and optional ideal-answer notes), and **Duplicate**, delete and **Save** controls. Questions are reordered by dragging the handle on the left of each row.

### Report

The scored result for one candidate. From top to bottom:

| Area | Contents |
|---|---|
| Header | Candidate name, template, format, completion time, **Export PDF** |
| Warning banners | *Not evaluated* or *Heuristic scoring*, when applicable |
| Score summary | A circular gauge with the overall score and a recommendation badge |
| AI Summary | A paragraph, plus **Strengths** and **Areas to improve** |
| KPI Profile | A radar chart of the scoring criteria |
| KPI Scores | Horizontal bars, one per criterion |
| Integrity | Counts of tab switches and logged events, when there are any |
| Per-question breakdown | An expandable row per question with the answer, per-criterion scores and feedback |
| Call recording | A video player (Two-way only) |
| Interviewer review | A 0–5 star rating and private notes (Two-way only) |
| Interview transcript | The full conversation |
| Facial analysis | Engagement summary (Video Interview only) |
| Signal analytics | Speech metrics and a communication/sentiment read |

![Screenshot: A candidate report showing the score gauge at 84 with a "Strong Yes" badge, the AI Summary panel, and the KPI radar chart](placeholder)

### Pipelines

A list of your multi-round hiring flows. Filters at the top: **Role**, **From** date, **To** date, and **Clear**. Each card shows the role, the number of rounds and their names in order, and the creation date.

### Pipeline board

A horizontally scrolling board. There is one column per round, plus **Selected** and **Not advancing** at the end.

Each column header shows its name and the number of candidates in it. Round columns also have a quick-advance bar: a dropdown (**Score ≥** or **Top N**), a number, and **Apply**. The **Selected** column has an **Export CSV** button when it contains anyone.

Each candidate card shows their name and email, a status badge, their score, and the actions available: **Advance →**, **Not advancing**, **Move back** and **History**. Cards that can be advanced have a highlighted border and a drag handle.

![Screenshot: The pipeline board with Screening, Technical, Final, Selected and Not advancing columns, and a candidate card being dragged between two rounds](placeholder)

### Live interview room (recruiter)

A full-screen dark room with no navigation bar. The top bar shows **Live interview**, a **Live** indicator, a **Rec** indicator while recording, any **Admit** buttons for waiting candidates, and **End interview**. The main area shows the candidate large with your own video small in the corner. The bottom bar has microphone, record, end call and camera buttons.

### Analytics

A dashboard of aggregate results. Filters at the top: **Track**, **Template**, **Role**, **From**, **To** and **Clear**.

Below the filters: summary cards; a score-distribution chart; an average-score trend; per-criterion averages; a by-track comparison; a recommendations breakdown; by-role and by-template tables; and a top-candidates list.

Several panels only appear once you select a role or template — see [4.9 Analytics](#49-analytics).

![Screenshot: The Analytics dashboard with the filter bar, four summary cards, and the score distribution and trend charts side by side](placeholder)

## 3.5 Avatar screening screens

### Avatar studio

Configures the AI video presenter. The page header has three buttons: **Apply to Candidate Interviews**, **Launch Test Session** and **Save Draft**, with a status line below confirming whether an avatar is currently applied.

Below that: any saved drafts, a **Tavus Configuration** panel, an informational note explaining that questions come from invitations, a **Session Properties** panel, and an **S3 Recording Storage** panel that appears only when recording is switched on. A live request preview sits in the right column on wide screens.

### Interview room

The live avatar call. Runs the face-framing check first, then shows the call. Contains a progress bar, a **Full Screen** button, a status line reading either *Interviewer is speaking* or *Listening — please answer*, a question counter, a transcription indicator, and **End Interview**.

### Results

The avatar-screening analytics dashboard. Contains an overall score ring with a verdict, four summary cards, dimension scores, an emotion dashboard (radar, category breakdown, timeline, heatmap and per-question cards), voice and signal analytics, strengths and watch points, an interview timeline, an AI recommendation panel, the full transcript, an AI assessment section, a facial analysis section, and a **Recruiter Actions** panel.

> This screen is separate from the per-candidate **Report** described above. **[NEEDS INPUT]** — please confirm how recruiters should be told to choose between them.

### Replicas

A grid of avatar faces. Each card shows a looping preview video, the name, the identifier, a status badge, a training progress bar while training, the creation date and a **Delete** link. Clicking a card opens a details panel where you can rename it.

### Personas

A grid of avatar behaviour profiles. Each card shows the name, identifier, the AI model in use, and the first lines of its instructions, with **Edit** and **Delete**. The editor is a large panel covering identity, the AI model, the speaking voice, the listening settings, environment awareness and camera vision, with a live preview of the configuration.

### Settings

Panels, in order: **Tavus — Avatar** (key entry and connection test), **Gemini API Key (AI Interview)**, **Analysis Providers — Server-Side** (read-only status for three services), **Webhook Configuration**, and **Platform Settings** (three toggles). Two buttons at the bottom: **Save Settings** and **Reset to Defaults**.

## 3.6 Mimic Guide

Mimic Guide is the assistant available on every screen once you are signed in.

| Element | What it does |
|---|---|
| Floating **Mimic Guide** button (bottom-right) | Opens the assistant |
| Panel header | The title, plus **Autopilot**, **Voice**, a speaker icon, **Clear chat** and a close button |
| Voice language selector | Choose from 55 languages for speech input and spoken answers |
| Suggested prompts | Four starter questions, shown when the conversation is empty |
| Message area | Your questions and the assistant's answers, with **Listen** under each answer |
| Typing box | Type a question and press Enter, or click the microphone |
| Autopilot strip | Appears when Autopilot is on: a progress line, an action log, and a confirmation card |
| Floating voice pill | Appears when Voice mode is on and the panel is closed |

![Screenshot: The Mimic Guide panel open on the right side of the screen showing a conversation, the voice language selector, and the Autopilot and Voice toggles in the header](placeholder)

---

# 4. Core Features

## 4.1 Managing your account

### 4.1.1 Sign in

1. Go to the sign-in page.
2. Type your **Email**.
3. Type your **Password**.
4. Click **Sign in**.

**Result:** you are taken to Sessions (recruiters) or Your interviews (candidates).

**If it fails:** see [8.1 Sign-in and account errors](#81-sign-in-and-account-errors).

### 4.1.2 Create an account

1. On the sign-in page, click **New here? Create an account**.
2. Under **I am a**, click **Candidate** or **Recruiter**.
3. Type your **Full name** (optional).
4. Type your **Email** (required).
5. Type a **Password** (required, minimum 6 characters).
6. Click **Create candidate account** or **Create recruiter account**.

**Result:** your account is created and you are signed in.

### 4.1.3 Sign out

1. Click the exit icon at the far right of the navigation bar (recruiters) or **Sign out** at the top-right (candidates).

**Result:** you are returned to the sign-in page.

---

## 4.2 Interview templates

A **template** is a saved recipe for how an interview runs. It holds the format, where questions come from, timings, your scoring guide, your branding and your integrity rules. You build a template once and reuse it for every candidate applying for that role.

### 4.2.1 Create a template

1. Click **Templates** in the navigation bar.
2. Click **+ New template**.

**Result:** a template called *New template* is created with the role *Software Engineer*, and the editor opens automatically.

### 4.2.2 Fill in the Basics

1. In the **Basics** section, replace **Template name** with something recognisable, for example *Senior Backend Engineer — Screening*.
2. Type the **Role** you are hiring for.
3. Optionally type a **Seniority**, for example *Mid* or *Senior*.
4. Choose a **Track** from the dropdown:
   - *Chat — one question at a time (timed slots)*
   - *Chatbot — conversational (ChatGPT-style)*
   - *Voice — live spoken AI interviewer*
   - *Video Avatar (scaffold)*

### 4.2.3 Choose where questions come from

1. In the **Questions** section, choose a **Question source**:
   - **Fixed — pick a saved question set** — everyone gets the same questions.
   - **Adaptive — generated from résumé (Gemini)** — each candidate gets questions tailored to their own background.
2. **If you chose Fixed:** pick a set from the **Question set** dropdown. To build one now, click **Generate set from résumé** (see [4.3.4](#434-generate-a-question-set-from-a-résumé)).
3. **If you chose Adaptive on a Timed Q&A template:** type the **Number of questions**.
4. **If you chose Adaptive on a conversational template:** the settings live under **Conversation** instead — see the next step.

> If you choose Fixed and do not pick a set, the preview panel warns *⚠ No question set selected — sessions can't start*, and any interview built from this template will fail to begin.

### 4.2.4 Configure the conversation (Chatbot, Voice and Video Avatar)

1. Choose a **Mode** (not shown for Voice):
   - **Conversational — relaxed, no timers**
   - **Timed — proctored thinking + answer limits**
2. Choose a **Question style**: *Technical*, *Non-technical* or *Mixed*.
3. Choose a **Difficulty**: *Easy*, *Medium*, *Hard* or *Mixed*.
4. Set the question counts:
   - With *Mixed* style, set **# Technical** and **# Non-technical**. The total updates automatically.
   - Otherwise, set **Number of questions**.
5. Optionally type **Focus topics**, separated by commas, for example `system design, Kafka, leadership`.
6. Optionally adjust the **Interviewer tone** (default *friendly and professional*) and the **Language** (default *English*).
7. Decide about follow-ups:
   - Leave **Allow follow-up questions** off to ask exactly the number of questions you set.
   - Turn it on to let the interviewer probe answers, then set **Max follow-ups per question**.
8. **If Mode is Timed**, set **Thinking (s)**, **Answer (s)** and **Warning at (s)**, and choose whether to **Allow skipping thinking time** and **Allow early submit**.

### 4.2.5 Configure the voice and persona (Voice track only)

1. Choose an **Engine**. Leave it on *Gemini Live — native audio (recommended)*.
2. Choose a **Persona**. The description appears underneath.

   | Persona | Character |
   |---|---|
   | Friendly HR Screener | Warm, encouraging first-round screener who puts candidates at ease |
   | Rigorous Technical Interviewer | Sharp, focused engineer probing depth and problem-solving |
   | Warm Behavioral Interviewer | Empathetic interviewer exploring experience and collaboration |
   | Executive Panel Lead | Composed, senior leader assessing strategic thinking and presence |

3. Pick a **Voice** from the grid of sixteen. Selecting a persona sets its default voice; you can override it.
4. Click the ▶ button beside any voice to hear a short sample.
5. Choose whether to **Allow barge-in** — whether the candidate can interrupt the interviewer by speaking. On by default.
6. Optionally change the **Language** code (default `en-US`).

### 4.2.6 Configure the per-question timer (Chatbot and Video Avatar)

This adds a countdown to individual questions in an otherwise relaxed conversation. It is **on by default** for new conversational templates.

1. Turn **Enable a per-question countdown** on or off.
2. Set **Answer time per question (s)** — default 120.
3. Set **Warning at (s)** — default 15. The countdown ring changes colour at this point.
4. Choose whether to **Allow early submit** (default on).
5. Choose whether to **Auto-submit at 0** (default on).
6. Choose whether to **Time follow-up questions too** (default on), and if so set **Follow-up time (s)** — leave blank to match the main question time.
7. Optionally turn on **Add a short prep sub-timer before answering** and set **Prep time (s)**.
8. **For fixed question sets only:** set **Per-question overrides** by typing a different number of seconds beside any individual question. Leave blank to use the default.

> The clock only ever runs while the candidate is answering. It never runs during the greeting, the "are you ready?" step, the thinking pause, or the closing message.

![Screenshot: The Per-question timer section with the countdown enabled, showing the timing fields on the left and the Live preview countdown ring on the right](placeholder)

### 4.2.7 Configure timing (Timed Q&A only)

1. Set **Prep (s)** — how long the candidate reads the question before answering. Default 30.
2. Set **Answer (s)** — the answering window. Default 120.
3. Set **Warning at (s)** — default 15.
4. Choose whether to **Allow skipping preparation** (default on).
5. Choose whether to **Allow early submit** (default on).
6. Optionally set an **Overall time cap (s)** for the whole interview. Leave blank for no cap.

### 4.2.8 Set up your scoring guide

Mimic scores each answer against a set of criteria. Six are provided by default, each switched on with equal weight.

| Criterion | What it measures |
|---|---|
| Communication Clarity | Clear, articulate, easy to follow |
| Relevance to Question | Directly answers what was asked |
| Technical / Domain Depth | Demonstrates real expertise and substance |
| Structure & Conciseness | Well-organised; concise, no rambling |
| Problem-Solving | Logical reasoning and a sound approach |
| Professionalism / Confidence | Composed, confident, professional tone |

**To adjust them:**

1. Click the toggle beside any criterion to switch it off. Switched-off criteria are not scored.
2. Click into the label to rename it.
3. Click into the description to reword it.
4. Change the number in the **weight** box to make a criterion count for more or less. The percentage below updates immediately — weights are rescaled automatically so the enabled ones always total 100%.
5. Click **Add custom KPI** to add your own criterion, then rename it and set its weight.
6. Click the bin icon to remove a criterion entirely.

### 4.2.9 Set your branding

1. Type your **Company name**. This appears on the candidate's screens and emails.
2. Choose an **Accent color** using the colour square, or type a hex code.
3. Optionally paste a **Logo URL**.
4. Edit the **Welcome message** the candidate reads before starting.

### 4.2.10 Set your integrity rules

| Option | Default | Effect |
|---|---|---|
| Enforce fullscreen | Off | Asks the candidate to stay in fullscreen; leaving is recorded and warned |
| Detect tab switching | On | Counts window and tab changes, and warns the candidate |
| Disable paste in answers | On | Blocks pasting into the answer box and records the attempt |
| Disable copy | Off | Blocks copying from the answer box |
| Log integrity events | On | Surfaces all of the above in your report |
| Max tab-switch warnings | 3 | The limit shown in the candidate's warning counter |

**[NEEDS INPUT]** — the warning counter shows a limit, but no automatic consequence for exceeding it was identified. Please confirm what should happen when a candidate passes the limit.

### 4.2.11 Save, duplicate and delete

**To save:**

1. Click **Save template** in the top-right.

**Result:** a *Template saved* confirmation appears.

**To duplicate:**

1. Go to **Templates**.
2. Click **Duplicate** on the card.

**Result:** a copy is created with *(copy)* appended, and *Template duplicated* appears.

**To delete:**

1. Go to **Templates**.
2. Click the bin icon on the card.
3. Click **OK** on the confirmation dialog *Delete "\<name\>"?*

**Result:** the template is removed and *Template deleted* appears.

---

## 4.3 Question sets

A **question set** is a reusable, ordered list of questions. Attach one to a template to ask every candidate the same things.

### 4.3.1 Create a set

1. Click **Question sets** in the navigation bar.
2. Click **New set**.

**Result:** a set called *New set* is created and selected, and *Set created* appears.

### 4.3.2 Add and edit questions

1. Select the set in the left pane.
2. Click into the name field at the top of the right pane to rename it.
3. Click **Add question**.
4. Type the question into the large box.
5. Optionally type a **Category** — a short grouping label such as *Experience* or *Problem-Solving*.
6. Optionally type **Ideal-answer notes** — a description of what a strong answer contains. This improves scoring accuracy and is **never shown to the candidate**.
7. Repeat for each question.
8. Click **Save**.

**Result:** *Set saved* appears.

![Screenshot: The Question sets screen with the set list on the left and three questions in the editor, one being dragged by its handle](placeholder)

### 4.3.3 Reorder, duplicate and delete

**To reorder questions:**

1. Click and hold the drag handle at the left of a question.
2. Drag it to its new position and release.
3. Click **Save**.

The order you see is the order candidates will be asked.

**To duplicate a set:**

1. Select the set.
2. Click **Duplicate**.

**Result:** a copy named *\<name\> (copy)* is created and selected, and *Set duplicated* appears.

**To delete a set:**

1. Select the set.
2. Click the bin icon.
3. Click **OK** on *Delete "\<name\>"?*

**Result:** *Set deleted* appears.

### 4.3.4 Generate a question set from a résumé

Mimic can read a sample résumé and write a tailored question set for you.

1. Click **Generate from résumé** on the Question sets screen. (The same dialog is available from the template editor and the Sessions screen.)
2. Drag a **PDF** résumé onto the upload area, or click it to browse. The file must be a PDF and no larger than 10 MB.
3. Choose a **Question style**: *Technical*, *Non-technical* or *Mix*.
4. Set the counts:
   - With *Mix*, set **# Technical** and **# Non-technical** (0–25 each).
   - Otherwise set **Number of questions** (1–25).
   - The combined total must be between 1 and 25.
5. Choose a **Difficulty**: *easy*, *medium*, *hard* or *mixed*.
6. Optionally type a **Role**.
7. Optionally type a **Question set name**. Left blank, one is suggested for you.
8. Choose a model: **flash** or **pro**.
9. If no AI key has been saved, a **Gemini API key** field appears — paste one here, or click the link to save it in Settings instead.
10. Click **Generate questions**.
11. Review the results. For each question you can edit the text, change its type between *technical* and *non-technical*, change its difficulty, or delete it with the bin icon. Click **Add question** to write your own.
12. Adjust the **Question set name** if needed.
13. Click **Save question set**.

**Result:** *Saved "\<name\>" (N questions)* appears and the new set is selected.

**If it fails:** see [8.4 Question-generation errors](#84-question-generation-errors).

---

## 4.4 Creating a single interview

Use this to interview one person quickly. For more than a handful, use the bulk wizard instead.

1. Click **Sessions** in the navigation bar.
2. Click **+ Single link**.
3. Choose a **Template** from the dropdown. The question source appears in brackets after each name.
4. Type the **Candidate name**. Left blank, the candidate is recorded as *Candidate*.
5. Type the **Candidate email**. This is **required** — it is how the candidate is granted access, and they must sign in with this exact address.
   > **[NEEDS INPUT]** — this field is not visibly marked as required and its format is not checked before you click Create. Leaving it blank fails with *A candidate email is required to assign this interview*. Please confirm whether the field should be marked required in the interface.
6. Optionally choose an **Interview mode (optional override)** to run this one interview in a different format from the template's:
   - *Use template default*
   - *Chatbot — conversational, typed*
   - *Voice — live spoken AI interviewer*
   - *Timed Q&A — 30s prep + 2 min answer*
   - *Conversational AI — Video Avatar*
7. Set the **Per-question timer**:
   - Turn it off for a relaxed conversation with no countdown.
   - Leave it on and set **Answer time per question (seconds)** — minimum 10. The hint below shows the resulting time in minutes and seconds.
8. Click **Create session**.
9. Copy the link that appears using **Copy**, and send it to the candidate. Click **Open as candidate ↗** to preview the interview yourself.
10. Click **Close**.

**Result:** *Session created* appears and the interview shows in the Sessions table with the status *created*.

> **Choosing Video Avatar without a configured avatar:** the dialog closes, a message appears — *Configure your AI avatar once — it then applies to all Conversational AI candidates* — and you are taken to Avatar studio. Configure and apply the avatar, then return and try again.

![Screenshot: The "New interview session" dialog with template, candidate name and email fields, the interview mode dropdown, and the per-question timer toggle](placeholder)

---

## 4.5 Inviting candidates in bulk

The invite wizard sets an interview up once and sends it to everyone. You never upload résumés here — each candidate uploads their own when they begin.

### Step 1 — Basics

1. Click **Sessions**, then **Invite candidates**.
2. Choose an **Interview type**:
   - **Single Interview** — one interview per candidate. This is the default.
   - **Multiple Rounds** — an ordered sequence of rounds candidates progress through.
3. **For Single Interview only,** choose an **Interview mode**:

   | Mode | Description |
   |---|---|
   | Chatbot | Conversational, typed — ChatGPT-style |
   | Voice | Live spoken AI interviewer |
   | Video Avatar | Conversational AI video avatar |
   | Timed Q&A | 30s prep + timed answers |
   | Video Interview | Candidate records webcam answers per question |
   | Two-way Interview | Live recruiter ↔ candidate video interview |

4. Type the **Candidate role**, for example *Senior Backend Engineer*. It must be at least 2 characters. Every invitation in this batch uses it, and you can override it per person in Step 3.
5. Click **Next: Questions →**.

> Choosing **Video Avatar** without a configured avatar shows *Configure your AI avatar once — it then applies to every candidate in this batch* and takes you to Avatar studio. Apply an avatar, and you are returned here with the mode already selected.

### Step 2 — Questions (Single Interview)

1. Choose a question source:
   - **Tailor questions to each résumé** — each candidate uploads their own résumé and gets a unique set generated from it.
   - **Your question sets** — reuse a set you have saved.
2. **If you chose Tailor:**
   1. Confirm the **Role** shown (read-only, from Step 1).
   2. Choose a **Question style**: *Technical*, *Non-technical* or *Mix*.
   3. Set the counts — **# Technical** and **# Non-technical** with *Mix*, otherwise **Number of questions**. The total must be between 1 and 25.
   4. Choose a **Difficulty**: *easy*, *medium*, *hard* or *mixed*.
   5. Optionally add **Domains** — focus areas such as *Distributed systems*. Type one and press Enter or click **Add**. Click the × on a chip to remove it.
   6. Choose a **Model**: *flash* or *pro*.
3. **If you chose Your question sets:** click the set you want. Click **+ Create new set** to build one now.
4. Click **Next: Candidates →**.

> **Two-way Interview** skips this: a live recruiter-led call has no scripted questions. You see an explanatory panel and continue.

### Step 2 — Rounds (Multiple Rounds)

Three rounds are provided by default: **Screening**, **Technical** and **Final**.

1. For each round:
   1. Type a **Round name**.
   2. Choose a **Mode**: Chatbot, Voice, Video Avatar, Timed Q&A or Video Interview. *(Two-way Interview is not available for pipeline rounds.)*
   3. Optionally choose an **Advance rule** — *Score ≥* or *Top N* — and type its **Value**. Defaults are 60 and 5. This pre-fills the quick-advance bar on the board later; it does not advance anyone by itself.
2. Drag a round by its handle to reorder it.
3. Click **Add round** to add another, or the bin icon to remove one. At least one round is required.
4. Click **Next: Candidates →**.

![Screenshot: The Round builder showing three rounds — Screening, Technical and Final — each with a name, mode and advance rule](placeholder)

### Step 3 — Candidates

1. Add candidates using either method:

   **From a file:**
   1. Drag a file onto the upload area, or click it to browse.
   2. Accepted formats: CSV, Excel, PDF, DOCX or TXT, up to 10 MB.
   3. Wait for *Reading file…* to finish.

   **By hand:**
   1. Type an address into **Or type an email: name@company.com**.
   2. Press Enter or click **Add email**.

2. Review the table. Each row shows a green ✓ for a valid address or a red ! for an invalid one, the email, and the role.
3. Correct any invalid addresses by clicking into the email box and editing it.
4. Override an individual **Role** by typing into that row.
5. Use **Remove invalid** to drop every flagged row at once, or **Clear all** to start again. Click the bin icon to remove a single row.
6. Read any warnings shown in the amber panel — these explain how the file was interpreted.
7. Click **Next: Invite email →**.

> Spreadsheets with an email column heading are read column by column, and a role column is used if one is present. Files without a header row, and unstructured files such as PDFs, have addresses extracted by pattern, and every role falls back to the batch role from Step 1 — read the warnings carefully in that case.

### Step 4 — Invite email

See [4.6 Designing the invitation email](#46-designing-the-invitation-email) for full details. In short:

1. Optionally load one of your **Saved templates** from the dropdown.
2. Set the **Sender**, **Subject** and **Body**.
3. Set the **Button & branding** options.
4. Click **Send test to me** to preview the real email in your own inbox.
5. Click **Next: Review →**.

The **Next** button stays disabled until the body or subject contains the interview link placeholder — see [4.6.4](#464-the-locked-interview-link).

### Step 5 — Review and send

1. Check the recipient list and the email preview.
2. Click **Send \<N\> invites**.

**Result:** a confirmation panel appears showing how many invitations were created, the batch reference, and how many emails were sent. Below it, a table lists every recipient with their status and link.

3. Copy an individual link with the copy icon beside it, or click **Copy all links** to copy every candidate and link together.
4. If a row failed, click **Retry** beside it.
5. Click **Done** to return to Sessions.

![Screenshot: The invite wizard success panel showing "24 invites created", the batch reference, and the recipient table with status badges and Retry links](placeholder)

**Status badges in the results table:**

| Badge | Meaning |
|---|---|
| accepted | The mail service accepted the message for delivery |
| delivered | Confirmed delivered to the recipient |
| opened / clicked | The candidate opened the email or clicked the link |
| bounced / spam / failed | Delivery failed — use **Retry** |
| pending | No send was attempted |

---

## 4.6 Designing the invitation email

Mimic sends four kinds of email. You can customise all of them.

| Kind | Sent when |
|---|---|
| **Invite** | You send invitations, or invite candidates into round 1 of a pipeline |
| **Advance** | You advance a candidate to the next round |
| **Selected** | You advance a candidate past the final round |
| **Rejection** | You mark a candidate as not advancing **and** explicitly opt in to emailing them |

### 4.6.1 Set the sender

1. Choose a **From address**:
   - If your mail service is connected, pick a verified sender from the dropdown, or choose *Use server default*.
   - Otherwise, type the address into the text field.
2. Type a **From name** — the display name recipients see.
3. Optionally type a **Reply-to** address.

> You can only send from a verified sender address. Sending from your own domain rather than the default shared subdomain requires your administrator to add and verify the domain with the mail provider.

### 4.6.2 Write the subject and body

1. Type a **Subject**. You can use placeholders such as `{{role}}`.
2. Write the **Body** in the rich-text editor.
3. Insert placeholders wherever you want personalised text.

**Available placeholders:**

| Placeholder | Replaced with | Available in |
|---|---|---|
| `{{candidate_name}}` | The candidate's name, derived from their email address | All emails |
| `{{role}}` | The role they applied for | All emails |
| `{{recruiter_name}}` | Your name | All emails |
| `{{company}}` | Your company name | All emails |
| `{{interview_link}}` | The candidate's unique interview link | Invite and Advance only |
| `{{deadline}}` | Your deadline text | Invite only |
| `{{round_name}}` | The round they are advancing to | Advance only |
| `{{previous_round_name}}` | The round they just completed | Advance only |
| `{{score}}` | Their score | Advance and Selected only |

### 4.6.3 Set the button and branding

1. Type the **Button text**, for example *Start your interview*.
2. Choose a **Button colour**.
3. Type your **Company name**.
4. Choose an **Accent colour** — this colours the top bar of the email.
5. Add a **Logo**, either by pasting a public direct image link or by clicking **Upload** to host one (maximum 2 MB, any image format).
6. Optionally set a **Footer** line.
7. Optionally set **Deadline text**, for example *Please complete within 5 days*.

> Google Drive links, Google Docs links and local addresses will not display in an email. Use **Upload** if you are unsure.

### 4.6.4 The locked interview link

`{{interview_link}}` **cannot be removed** from an invite or advance email — without it, the candidate has no way to reach their interview.

If it is missing you see: *The interview link ({{interview_link}}) is required and can't be removed*, and **Next** is disabled.

**To fix it:**

1. Click **Insert link** in the warning banner.

**Result:** the placeholder is added to the end of your message body and the warning clears.

Two further items are always added automatically at send time and cannot be removed:
- A note confirming which email address the invitation is tied to.
- A plain-text copy of the link, for recipients whose email client blocks buttons.

### 4.6.5 Send yourself a test

1. Click **Send test to me**.

**Result:** the email arrives at your own address with sample values filled in and `[TEST]` added to the subject. A *Test sent to \<your email\>* confirmation appears.

If your mail service is not fully connected you instead see *Dry-run: mailer not configured (would send to …)* — nothing was sent.

### 4.6.6 Save and reuse email designs

1. Design your email.
2. Click **Save** and type a name when prompted.

**Result:** *Template saved*. The design now appears in the **Saved templates** dropdown.

**Other controls:**

| Button | Effect |
|---|---|
| **Update** | Overwrites the currently loaded saved design |
| **Duplicate** | Creates a copy you can edit separately |
| **Delete** | Removes the saved design after a confirmation |
| **Save as new** | Saves the current state under a new name |

The first time you open the email step with nothing saved, a sensible default design is created for you automatically.

![Screenshot: The invite email designer with the configuration fields on the left and the live email preview on the right](placeholder)

---

## 4.7 Multi-round pipelines

A **pipeline** moves candidates through several rounds — for example Screening, then Technical, then Final. Each round is a real interview; candidates who pass move forward.

### 4.7.1 Create a pipeline

Pipelines are created through the invite wizard.

1. Click **Sessions**, then **Invite candidates**.
2. In Step 1, choose **Multiple Rounds** and type the **Candidate role**.
3. In Step 2, build your rounds — see [Step 2 — Rounds](#step-2--rounds-multiple-rounds).
4. Complete Steps 3, 4 and 5 as normal.

**Result:** the pipeline is created and everyone is invited to round 1. *Pipeline created — invited N to Round 1* appears.

### 4.7.2 Find a pipeline

1. Click **Pipelines** in the navigation bar.
2. Optionally narrow the list:
   - Choose a **Role**.
   - Set a **From** and/or **To** date.
   - Click **Clear** to remove all filters.
3. Click a pipeline card to open its board.

### 4.7.3 Read the board

Each column is a round, followed by **Selected** and **Not advancing**.

**Card badges:**

| Badge | Meaning |
|---|---|
| Invited | The candidate has been sent this round but has not started |
| In progress | They are partway through |
| Scored | They finished and have been scored — they can now be advanced |
| Expired | The round is no longer available |

A card can only be advanced once it shows **Scored**. Those cards have a highlighted border and a drag handle.

### 4.7.4 Advance one candidate

**By dragging:**

1. Click and hold the drag handle on the card.
2. Drag it to the next round's column, or to **Selected** if they are in the final round.
3. Release.

**By button:**

1. Click **Advance →** on the card.

Either way the confirmation panel opens. Continue at [4.7.7](#477-confirm-and-send-a-transition).

> You can only move a candidate to the **immediate next** round. Dropping anywhere else shows *Can only advance to the next round* and nothing happens.

### 4.7.5 Advance a group by score

1. In a round column, choose a rule from the dropdown:
   - **Score ≥** — everyone at or above a score.
   - **Top N** — the highest-scoring N candidates.
2. Type the number.
3. Click **Apply**.

**Result:** the confirmation panel opens listing everyone who qualified.

If nobody qualifies you see *No candidates in this round meet that criteria*. Candidates with no score are never selected by either rule.

### 4.7.6 Mark a candidate as not advancing

1. Click **Not advancing** on the card, or drag it to the **Not advancing** column.
2. In the panel, decide whether to email them:
   - Leave **Send a rejection email** off to move them silently. The button reads **Move without emailing**.
   - Turn it on to write and send a rejection. The button reads **Confirm & send**.
3. Click the button.

**Rejection emails are off by default.** Candidates can be moved without ever being contacted.

### 4.7.7 Confirm and send a transition

The same panel handles advancing, selecting and rejecting.

1. Review the **Recipients** list — names, emails and scores.
2. Review or edit the **Subject**.
3. Review or edit the **Body**.
4. Check the **Preview** — this is exactly what will be sent.
5. Click **Confirm & send**.

**Result:** the **Results** view lists each recipient with one of three badges:

| Badge | Meaning |
|---|---|
| Email sent | Moved and emailed successfully |
| Moved · email failed | **The candidate was moved.** Only the email failed |
| Moved | Moved, with no email requested |

6. Click **Close**.

> If some emails fail, the panel explains: *Candidates were moved successfully. Some emails didn't send — the reason is shown per recipient.* The advancement itself has already happened and does not need repeating.

### 4.7.8 Undo an advance

1. Click **Move back** on the card.
2. Click **OK** on the confirmation *Move this candidate back to the previous round? This deletes their next-round link; the email can't be unsent.*

**Result:** *Moved back to the previous round* appears; the candidate returns to their previous round and the new round's interview link stops working.

**Move back is only available when all of these are true:**
- The candidate is in an active round (not Selected or Not advancing).
- They are past the first round.
- They have **not** completed the round they were advanced into.

The advance email that has already gone out cannot be recalled.

### 4.7.9 View a candidate's history

1. Click **History** on the card.

**Result:** a list of every action taken, in the form *Advanced Screening → Technical · 14 March 2026, 10:22 · confirm-modal · email accepted*.

Recorded actions are: Invited, Advanced, Selected, Not advancing and Moved back.

### 4.7.10 Export the selected candidates

1. Click **Export CSV** at the top of the **Selected** column.

**Result:** a file named `<role>-selected.csv` downloads, containing *Name*, *Email* and *Final score*.

The button only appears when at least one candidate has been selected.

---

## 4.8 Reading a candidate report

### 4.8.1 Open a report

1. Click **Sessions**.
2. Find the candidate. Reports are available once the status is **completed**.
3. Click **View report →**.

You can also reach reports from **Analytics** by clicking any name in **Top Candidates**.

### 4.8.2 While scoring is in progress

If the interview has just finished you see *Scoring in progress… This updates automatically when the analysis is ready.* Leave the page open — it refreshes itself every few seconds.

### 4.8.3 Understand the score

The gauge shows the **overall score** out of 100 — a weighted average of your enabled criteria, calculated by Mimic rather than by the AI model.

The badge beneath it is the **recommendation**:

| Recommendation | Overall score |
|---|---|
| **Strong Yes** | 80 or above |
| **Yes** | 65 to 79 |
| **Maybe** | 50 to 64 |
| **No** | Below 50 |

### 4.8.4 Read the detail

1. Read the **AI Summary**, plus **Strengths** and **Areas to improve**.
2. Check the **KPI Profile** radar chart for the overall shape of the candidate's performance.
3. Check **KPI Scores** for the exact number per criterion.
4. Review the **Integrity** chips if present — the number of tab switches and logged events.
5. Click any row in **Per-question breakdown** to expand it. You will see:
   - The answer, or a recorded clip with its transcript.
   - A score chip for each criterion.
   - Written **Feedback** for that answer.
   - An **auto** marker if the answer was submitted automatically when time ran out.
   - The time used, where recorded.
6. Scroll to **Interview transcript** for the complete conversation.
7. Read **Signal analytics** at the bottom:
   - **Speech metrics** / **Response metrics** — word count, number of answers, average words per answer, filler-word count and rate, vocabulary variety and average reply time.
   - **Communication & sentiment** — an overall tone label plus confidence, clarity and positivity bars, and a short written read.

> Sentiment is derived from the **words** in the transcript, not from tone of voice. The report says so explicitly.

### 4.8.5 Watch for the two warning banners

| Banner | Meaning | What to do |
|---|---|---|
| **Not evaluated** | No candidate answers were captured. The zeros are placeholders, not a judgment. | Ask the candidate to retake the interview, or check the avatar/voice configuration in Settings |
| **Heuristic scoring** | No AI key is configured, so scores reflect answer length only | Add an AI key in Settings, then re-run the interview |

### 4.8.6 Rate a live interview yourself (Two-way only)

1. Scroll to **Interviewer review**.
2. Click a star from 1 to 5. Click the same star again to clear the rating.
3. Type your **private notes**. These are for your hiring team and are never shown to the candidate. Up to 4,000 characters.
4. Click **Save review**.

**Result:** *Review saved* appears, along with a line showing when it was last saved and by whom.

You can save a review before AI scoring has finished.

### 4.8.7 Export a report as PDF

1. Click **Export PDF** in the top-right.

**Result:** a file named `TalbotIQ-<Candidate-Name>-report.pdf` downloads.

The button only appears once the report exists.

---

## 4.9 Analytics

### 4.9.1 Open and filter the dashboard

1. Click **Analytics** in the navigation bar.
2. Narrow the results using any combination of:
   - **Track** — one of the six interview formats, or *All tracks*
   - **Template** — a specific template, or *All templates*
   - **Role** — a role, or *All roles*
   - **From** and **To** — a date range
3. Click **Clear** to remove all filters.

### 4.9.2 Why some panels are hidden

**Average Score**, **Score Distribution**, **KPI Averages** and **Top Candidates** appear only once you select a **Role** or a **Template**.

This is deliberate: averaging or ranking candidates across completely different jobs is misleading. The dashboard tells you so: *Select a Role or Template above to see the average score, score distribution, KPI averages, and top candidates for that position.*

### 4.9.3 What each panel shows

| Panel | Contents |
|---|---|
| **Interviews Created** | How many were created, with started and completed counts |
| **Completion Rate** | Completed as a percentage of created |
| **Average Score** | Mean overall score across scored interviews *(role/template only)* |
| **Avg Duration** | Average interview length, and the average per question |
| **Score Distribution** | How many candidates fell into each band: 0–20, 21–40, 41–60, 61–80, 81–100 *(role/template only)* |
| **Average Score Trend** | Average score by completion day |
| **KPI Averages** | Average per criterion, with a *coverage* figure showing what share of interviews used it *(role/template only)* |
| **By Track** | Sessions, average score and completion rate per format |
| **Recommendations** | How many Strong Yes / Yes / Maybe / No / Unscored, plus the integrity flag rate |
| **By Role** | Sessions and average score per role |
| **By Template** | Sessions and average score per template |
| **Top Candidates** | The ten highest scorers, clickable through to their reports *(role/template only)* |

### 4.9.4 Open a top candidate's report

1. Select a **Role** or **Template** so the **Top Candidates** panel appears.
2. Click a candidate's row.

**Result:** their full report opens.

Only scored interviews contribute to these figures. The footer shows when the data was aggregated.

---

## 4.10 Avatar studio

Avatar studio configures the AI video presenter used by Video Avatar interviews.

### 4.10.1 Choose the avatar

1. Click **Avatar studio**.
2. Pick a face from the **Replica** dropdown, or paste an identifier into the **or enter ID** field.
3. Optionally choose a **Persona** to control its behaviour. Left as *None*, it uses the replica's own defaults.

The line under the field confirms your choice and tells you how many custom and stock faces are available.

### 4.10.2 Set the avatar's voice and script

1. Type an **AI Interviewer Name** — what the avatar calls itself. Default *Alex*.
2. Type a **Conversation Name** — a base label; the candidate's name is added automatically.
3. Write the **Conversational Context** — the instructions describing how the avatar should behave, for example: *You are Alex, a Senior Talent Specialist at TalbotIQ. Ask each question clearly and wait for the candidate's full response before proceeding. Maintain a warm, professional tone throughout.*
4. Write a **Custom Greeting** — the avatar's first words.
5. Optionally set a **Callback URL** to receive event notifications.

> **Questions are not set here.** They come from the invitation — either tailored to each candidate's résumé or taken from your question set — and are inserted into the avatar's script automatically.

### 4.10.3 Set the session properties

1. Choose a **Language**: English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Hindi or Arabic.
2. Choose a **Pipeline Mode**: *Full — audio + video*, *Echo — test mode*, *No audio* or *Video only*.
3. Drag **Max Call Duration** to set the limit, between 1 minute and 2 hours.
4. Set **Participant Left Timeout (s)** and **Absent Timeout (s)**.
5. Set the toggles:

   | Toggle | Default | Effect |
   |---|---|---|
   | Enable Transcription | On | Real-time transcription of candidate speech |
   | Enable Recording | Off | Saves the session video |
   | Conversation Override | Off | Allows text to be injected during the call |
   | Virtual Background | Off | Replaces the avatar's background with an image |

6. If you turned on **Virtual Background**, paste a **Background Image URL**.
7. If you turned on **Enable Recording**, fill in the **S3 Recording Storage** panel: **Bucket Name**, **Region** and **AWS Assume Role ARN**.

### 4.10.4 Apply the avatar to candidate interviews

1. Click **Apply to Candidate Interviews**.

**Result:** *Applied — every Conversational AI candidate interview now uses this avatar.* The status line confirms which face is applied and when it was last updated.

Until you do this, the status reads *No avatar applied yet — candidate Conversational AI interviews won't start until you apply one*, and Video Avatar interviews cannot begin.

### 4.10.5 Test the avatar yourself

1. Click **Launch Test Session**.
2. Type a **Candidate Name**.
3. Click **Launch Interview**.

**Result:** *Session created!* and the live avatar room opens.

**If the avatar service returns an error,** a panel shows the message and offers:
- **Continue in Demo Mode (no avatar)** — opens the room without avatar video
- **Try Again**
- **Dismiss**

If the message mentions credits, additional guidance appears about purchasing more from your avatar provider.

**Running without an avatar:** if no replica is selected, clicking **Launch Interview** starts Demo Mode directly and shows *Running in Demo Mode — no avatar video*.

### 4.10.6 Save and reuse configurations

**To save:**

1. Click **Save Draft**.
2. Type a **Draft Name**.
3. Click **Save Draft** (or press Enter).

**Result:** *Draft "\<name\>" saved*. It appears in the **Saved Drafts** panel with its question count and save time.

**To load:** click the draft card. *Loaded "\<name\>"* appears.

**To delete:** hover the card and click the × in its corner. *Draft deleted* appears.

![Screenshot: Avatar studio with the replica picker, the AI Interviewer Name and Custom Greeting fields, and the request preview panel on the right](placeholder)

---

## 4.11 Replicas and personas

### 4.11.1 Browse avatar faces

1. Click **Avatar studio**, then navigate to **Replicas**. **[NEEDS INPUT]** — Replicas is not on the main navigation bar; please confirm the intended route.
2. Each card shows a looping preview, the name, the identifier, a status badge and the creation date.
3. Cards still training show a progress bar.

### 4.11.2 Rename an avatar face

1. Click the card.
2. Edit **Rename Replica**.
3. Click **Save Changes**.

**Result:** *Replica renamed*.

### 4.11.3 Delete an avatar face

1. Click **Delete** at the bottom of the card.
2. Click **OK** on *Delete "\<name\>"?*

**Result:** *Replica deleted*.

### 4.11.4 Add a new avatar face

Faces are created in the avatar provider's own dashboard, not in Mimic.

1. Click **+ New Replica**.

**Result:** guidance appears — *Create replicas at platform.tavus.io → Replicas → Create. They appear here automatically once training completes (~15 min).*

### 4.11.5 Create a persona

A **persona** is a saved behaviour profile for the avatar.

1. Go to **Personas** and click **+ New Persona**.
2. Under **Identity**:
   1. Type a **Persona Name**.
   2. Optionally choose a **Default Replica**.
   3. Write the **System Prompt** — the instructions defining the character. Up to 4,096 characters.
   4. Optionally add **Context** — background about the role, company or candidate.
3. Under **LLM Layer**, choose a **Model** and set **Max Tokens** (1–4,096) and **Temperature** (0 = predictable, 2 = creative).
4. Under **TTS Layer**, choose a **TTS Engine**, set the **Speaking Speed** (0.5×–2×) and click any **Voice Emotions** to apply.
5. Under **STT Layer**, choose an **STT Engine**, set **Pause Sensitivity** and toggle **Smart Turn Detection**.
6. Under **Perception Layer**, click **+ Add query** to add environment questions such as *Is the candidate in a quiet environment?*
7. Under **VQA Layer**, toggle **Enable Camera (VQA)** to let the avatar respond to what it sees.
8. Click **Create Persona**.

**Result:** *Persona created*.

### 4.11.6 Edit or delete a persona

1. Click **Edit** on the card, change what you need, then click **Save Changes**. *Persona updated* appears.
2. Or click **Delete**. *Deleted* appears.

---

## 4.12 Running a live two-way interview

A Two-way Interview is a real video call between you and the candidate, recorded and scored afterwards.

### 4.12.1 The order of events matters

**The candidate must open their invitation link before you can start the room.**

1. You invite them using the wizard with the **Two-way Interview** mode.
2. **The candidate opens their link.** Their screen shows a lobby and retries automatically. This first visit is what makes the interview appear in your Sessions list.
3. You refresh **Sessions**. The interview now appears.
4. You click **Join live interview →**.
5. The candidate's next automatic retry succeeds and they knock to enter.
6. You admit them and the call begins.

If you try to join before they have ever opened their link, you see: *The candidate must open their interview link before you can join.*

**[NEEDS INPUT]** — this candidate-first ordering is a known limitation of the current version: there is no scheduled start time, and a recruiter cannot open the room before the candidate has ever visited. Please confirm whether this is the procedure to publish, or whether scheduling is expected first.

### 4.12.2 Host the call

1. Click **Sessions**.
2. Find the Two-way interview and click **Join live interview →**.
3. Wait while *Starting the interview room…* appears.
4. When the candidate knocks, click **Admit \<name\>** in the top bar.
5. Conduct the interview.

### 4.12.3 Record the call

1. Click the record button (the disc icon) in the bottom bar to start.

**Result:** a red **Rec** badge appears in the top bar.

2. Click it again to pause. Click once more to resume.

The whole call is captured as a single recording — pausing and resuming never loses a segment.

### 4.12.4 Control your audio and video

| Control | Effect |
|---|---|
| Microphone button | Mutes and unmutes you. A red icon means muted |
| Camera button | Turns your camera off and on. A red icon means off |

### 4.12.5 End the call

1. Click **End interview**.
2. Click **OK** on *End the interview now? The recording will be uploaded and the session will be marked complete.*
3. Wait for *Uploading recording…* and then *Finalizing…*

**Result:** you are taken to the candidate's report. The recording is transcribed and scored in the background.

If the candidate leaves first or the connection drops, the same finishing process runs automatically without asking you to confirm. If it seems slow, a **Go to report** button is available.

![Screenshot: The recruiter's live interview room with the candidate on the main video, a small self-view, the Rec badge, and the call controls at the bottom](placeholder)

---

## 4.13 Taking an interview (candidates)

### 4.13.1 Open your interview

1. Open your invitation email.
2. Click **Start your interview**.
3. If prompted, sign in — or create an account — using **the exact email address the invitation was sent to**.

**Alternatively:**

1. Sign in and go to **Your interviews**.
2. Click **Start interview** (or **Continue** if you began earlier).

If you signed in with the wrong address, Mimic explains which address you are using and offers **Sign out & switch account**.

### 4.13.2 Choose your format (when offered)

Some interviews let you pick how you would like to be interviewed. All options ask the same questions and are timed identically.

1. Click **Chat Interview**, **Voice Interview** or **Video Avatar**.
2. Click **Continue**.

### 4.13.3 Read the welcome screen

1. Read the welcome message and the three rules:
   - How long you get to prepare and to answer.
   - That answers submit automatically when time runs out, and you cannot go back.
   - That questions appear one at a time and upcoming ones stay hidden.
2. Click **Continue**.

### 4.13.4 Provide your name and résumé (when asked)

1. Type **Your full name** — at least two characters. The AI interviewer uses this to address you.
2. Click the upload area and choose your résumé. Accepted: PDF, DOCX or TXT, up to 8 MB.
3. Click **Continue**.

**Result:** *Preparing your questions…* appears while your questions are written, then you move on.

### 4.13.5 Complete the readiness check

**Standard check:**

1. Read the three reminders: a stable connection, a quiet space, and enough uninterrupted time.
2. Tick **I understand the rules and I'm ready to begin**.
3. Click **I'm ready, begin**.

**Video Interview consent:**

1. Read the three points about camera, microphone and your environment.
2. Tick **I understand my responses are recorded and analysed by AI, and reviewed by a human recruiter**.
3. Click **I consent — begin**.

**Camera and microphone check (Video Avatar and Two-way):**

1. Click **Enable camera & microphone**.
2. Allow access when your browser asks.
3. Check yourself in the preview. *Camera ready* and *Mic ready* confirm success.
4. Click **I'm ready, begin**.

If you blocked access you see *Permission was blocked. Enable camera & mic access in your browser, then retry.* Change the setting in your browser's address bar and reload.

### 4.13.6 Position your face (Video Avatar)

1. Look at the camera with your whole face visible.
2. Move so your face fits inside the outline.
3. Hold still briefly until it locks.

**Tips shown on screen:**
- Face the camera with your whole face visible
- Use even, front-facing lighting — avoid strong backlight
- Remove hats, sunglasses, or masks
- A plain, quiet background works best

**Result:** *Perfect — you're all set* appears and your interview starts.

If it does not lock after a while, a "Having trouble?" option appears so you can continue anyway. This step is only a framing aid — it is not part of your assessment.

### 4.13.7 Answer timed questions (Timed Q&A)

1. Read the question during the **Preparation** phase. The countdown ring shows your remaining time.
2. Optionally click **Start answering now** to begin early.
3. When the ring switches to **Answering**, type your answer. A word count appears below the box.
4. Click **Submit & continue** when you are done.

**If you run out of time,** your answer submits automatically. A red warning appears first: *\<n\>s left — your answer will auto-submit at zero.*

**Useful to know:**
- Your typing is saved continuously. If you refresh or lose connection, you return to the same question with your text intact and the correct remaining time.
- You cannot return to a previous question.
- Pasting may be blocked. If so, a warning is recorded.
- A tip on screen suggests structuring answers using **STAR** — Situation, Task, Action, Result.

### 4.13.8 Take a chat interview (Chatbot)

1. Read the greeting. It ends by asking whether you are ready.
2. From the dropdown, choose **Yes, I'm ready** or **No, not yet**, then click **Send**.
3. **If you chose "No, not yet",** pick how long you need — **30 seconds**, **45 seconds** or **1 minute** — or click **Actually, I'm ready now**. The interview starts automatically when the countdown ends.
4. Answer each question in the typing box. Press **Enter** to send, or **Shift + Enter** for a new line.
5. Wait while *Thinking…* appears between messages — this is the interviewer composing its reply.

**If a countdown ring appears** in the header, that question is timed:
- Answer before it reaches zero, or whatever you have typed is submitted for you.
- If a preparation window is enabled, the typing box unlocks when it ends, or when you click **Start answering now**.

**Result at the end:** *All done, thank you!*

### 4.13.9 Take a voice interview (Voice)

1. Read the introduction, then click **Start voice interview**.
2. Allow microphone access when your browser asks.
3. Speak naturally. The circle and the label show what is happening:

   | Label | Meaning |
   |---|---|
   | Connecting… | Setting up |
   | Interviewer is speaking | Listen |
   | Listening… | Your turn |
   | One moment… | The interviewer is thinking |
   | Interview complete | Finished |

4. Optionally click the captions button to read a live transcript.
5. Use the microphone button to mute and unmute.
6. Click the red **End interview** button when the interview is finished.

**If your connection stutters,** *Reconnecting…* appears with *Connection hiccup — your interview is saved and will resume in a moment.* Wait — it recovers by itself.

**At the end** you see either *All done, thank you!* or, if the connection dropped before the interview finished, *Interview interrupted* with guidance to contact the hiring team.

### 4.13.10 Take a video interview (Video Interview)

1. Allow camera access. Your live preview appears with a **Preview** label.
2. Read the question during the preparation phase.
3. Optionally click **Start recording now** to begin early.
4. When **Recording answer** appears, speak your answer aloud. A red **Rec** badge shows you are being captured.
5. Click **Submit & continue** when finished.

**Useful to know:**
- Your spoken words are transcribed live — the transcript is your answer.
- Your answer submits automatically shortly before the timer ends, so do not leave it to the last second.
- A warning shows *\<n\>s left — your answer submits automatically.*
- If submission fails you see: *Your answer may not have been submitted. If the interview advanced, that question could be missing its transcript.* Tell your recruiter.

### 4.13.11 Join a live interview (Two-way)

1. Open your interview link.
2. Complete the camera and microphone check.
3. Wait in the lobby. You will see one of:
   - *Waiting for the interviewer to start the interview…*
   - *Waiting for the interviewer to admit you…*
   - *Reconnecting…*
4. When admitted, the interviewer appears on the main video and you appear in the corner.
5. Use the microphone and camera buttons as needed.
6. Click **End interview** and confirm *End the interview now? You can't rejoin afterwards.* when the interview is over.

Waiting for the interviewer to start is normal and can take a while — the page keeps retrying by itself.

### 4.13.12 Understand the integrity warnings

Depending on your recruiter's settings, you may see warnings such as:

| Warning | Cause |
|---|---|
| *Please stay on this tab — switching away is recorded (1/3)* | You changed tab or window |
| *Please return to fullscreen for the interview (1/3)* | You left fullscreen |

Pasting and copying in the answer box may also be blocked. These events are recorded and shown to your recruiter. Stay on the interview tab and answer in your own words.

### 4.13.13 Finish

The final screen reads **All done, thank you!** with confirmation that your responses were submitted and that there is nothing more to do.

Scores are reviewed by the hiring team and are **not shown to candidates**.

---

## 4.14 Mimic Guide

Mimic Guide is the built-in assistant. It answers questions about the product and, with Autopilot enabled, can operate the product for you.

### 4.14.1 Ask a question

1. Click the **Mimic Guide** button in the bottom-right corner.
2. Click one of the suggested questions, or type your own into the box.
3. Press **Enter** or click the send button.

**Result:** an answer appears, often with a link that takes you straight to the relevant page. Clicking a link closes the panel and navigates there.

Your conversation is remembered across page loads. Click **Clear chat** to start again.

### 4.14.2 Ask in another language

1. Click the language dropdown beside the microphone icon in the header.
2. Search for your language, or scroll the list of 55.
3. Click it.

**Result:** speech input and spoken answers switch to that language. Suggested prompts appear in your language for Hindi, Marathi, Tamil, Telugu, Kannada and Malayalam; other languages show them in English.

If you write in a language other than English, the answer comes back in your language with the full English version in a collapsible **English** block underneath.

### 4.14.3 Speak instead of typing

1. Click the microphone button beside the typing box.
2. Speak. What you say appears in the box.
3. Click the microphone again to stop, then send.

If it stops responding, click **Restart** in the listening bar.

### 4.14.4 Listen to answers

- **Auto-speak** is on by default. Turn it off using the speaker icon in the header.
- Click **Listen** below any answer to hear it. Click **Stop** to interrupt.

If the voice cannot be produced you see *Couldn't play the voice for this language right now — please try again.*

### 4.14.5 Use hands-free Voice mode

Voice mode keeps listening even when the panel is closed and sends what you say automatically after a pause.

1. Click **Voice** in the panel header.
2. Close the panel if you wish. A floating pill appears at the bottom-left showing what is happening.
3. Speak a command. It is submitted automatically once you pause.
4. If a confirmation is requested, say **yes** or **no**.
5. Click the × on the pill to turn Voice mode off.

The pill shows: *Listening — speak a command*, *Working on it…*, *Awaiting confirmation — say "yes" or "no"*, or *Voice paused*. Tap the microphone to resume if it stops.

### 4.14.6 Use Autopilot

With Autopilot on, the assistant operates the interface for you.

1. Click **Autopilot** in the panel header.
2. Describe what you want, for example *set up a video interview for Senior Backend Engineer*.
3. Watch the strip below the header — it shows your current step and a log of actions taken.
4. **When an action would send something or change a candidate's status**, Autopilot pauses and shows a summary card. Read it, then click **Confirm** to proceed or **Cancel** to stop.

**What Autopilot can do:**

| Where | What it can do | Needs confirmation? |
|---|---|---|
| Anywhere | Navigate to a page | No |
| Invite wizard | Choose single or multi-round, select the mode, set the role, choose the question source, select a question set, add a candidate, move forward or back a step | Only *create and send invites* |
| Analytics | Filter by track, role or template; set a date range; clear filters; open a top candidate's report | No |
| Pipelines list | Open a board by role; filter by role; set a date range; clear filters | No |
| Pipeline board | Advance by score, advance the top N, advance one candidate, mark not advancing, move back | Yes, for all of these |
| Pipeline board | Export the selected list as CSV | No |

Autopilot can never skip a required step. If the current step is incomplete, asking it to move on does nothing until you fill in what is missing.

![Screenshot: Mimic Guide with Autopilot enabled, showing the step tracker, the action log, and a confirmation card with Confirm and Cancel buttons](placeholder)

---

## 4.15 Requesting a demo (public website)

1. Go to the Mimic public website.
2. Click **Book a demo**, or scroll to the form at the bottom.
3. Fill in:
   - **First name**
   - **Last name**
   - **Work email**
   - **Hires per year**, for example *500–2,000*
4. Click **Book a demo**.

**Result:** *Thanks — you're on the list. We'll be in touch within one business day to set up your walkthrough.*

**If a field is wrong,** a message appears beneath it — *Enter your first name.*, *Enter your last name.*, *Enter a valid work email.* or *Roughly how many people do you hire a year?*

**If sending fails:** *Something went wrong sending that. Please try again, or email sales@talbotiq.com.*

### 4.15.1 Use the ROI calculator

1. Go to **Resources → ROI calculator** on the public website.
2. Drag the three sliders:
   - **Applicants per month** — 50 to 5,000
   - **Minutes per manual screen** — 5 to 45
   - **Loaded recruiter cost / hour** — $20 to $120
3. Read the three results: recruiter hours returned per month, first-round cost returned per month, and the annual figure.

The page notes this is an estimate of manual first-round screening time, not a guarantee.

---

# 5. Settings & Configuration

This section lists every option you can change, its default, and what it does.

## 5.1 Template settings

### 5.1.1 Basics

| Option | Default | Allowed values | Effect |
|---|---|---|---|
| Template name | *New template* | Any text | Identifies the template in lists |
| Role | *Software Engineer* | Any text | The job title; used in generated questions and analytics grouping |
| Seniority | Empty | Any text | Refines generated questions |
| Track | *Chat* | Chat, Chatbot, Voice, Video Avatar | The interview format |

### 5.1.2 Questions

| Option | Default | Allowed values | Effect |
|---|---|---|---|
| Question source | *Fixed* | Fixed, Adaptive | Whether questions come from a saved set or are written per candidate |
| Question set | None | Any saved set | Which fixed questions to ask. Required when the source is Fixed |
| Number of questions | 5 | Whole number | How many questions to generate (adaptive, non-conversational formats) |

### 5.1.3 Conversation (Chatbot, Voice, Video Avatar)

| Option | Default | Allowed values | Effect |
|---|---|---|---|
| Mode | *Conversational* | Conversational, Timed | Whether question turns are timed. Hidden for Voice |
| Question style | *Mixed* | Technical, Non-technical, Mixed | The kind of questions generated |
| Difficulty | *Mixed* | Easy, Medium, Hard, Mixed | How demanding the questions are |
| # Technical | 3 | Whole number | Technical questions in a mixed interview |
| # Non-technical | 2 | Whole number | Non-technical questions in a mixed interview |
| Number of questions | 5 | Whole number | Total, when the style is not Mixed |
| Focus topics | Empty | Comma-separated list | Subjects to emphasise |
| Interviewer tone | *friendly and professional* | Any text | The interviewer's manner |
| Language | *English* | Any language name | The language of the interview |
| Allow follow-up questions | **Off** | On, Off | Whether the interviewer probes answers. Off means exactly the number of questions you set |
| Max follow-ups per question | 1 | Whole number | The limit when follow-ups are on |
| Allow follow-ups on the fixed set | Off | On, Off | Adds AI follow-ups between saved questions |
| Thinking (s) | 30 | Whole number | Preparation window in Timed mode |
| Answer (s) | 120 | Whole number | Answering window in Timed mode |
| Warning at (s) | 15 | Whole number | When the countdown turns amber/red |
| Allow skipping thinking time | On | On, Off | Lets the candidate start answering early |
| Allow early submit | On | On, Off | Lets the candidate submit before time is up |

### 5.1.4 Voice & persona (Voice only)

| Option | Default | Allowed values | Effect |
|---|---|---|---|
| Engine | *Gemini Live* | Gemini Live, STT → Gemini → TTS | The voice technology. The second option is labelled *coming soon* |
| Persona | *Friendly HR Screener* | Friendly HR Screener, Rigorous Technical Interviewer, Warm Behavioral Interviewer, Executive Panel Lead | The interviewer's character |
| Voice | *Aoede* | Sixteen voices (see below) | The speaking voice |
| Allow barge-in | On | On, Off | Whether the candidate can interrupt by speaking |
| Language | *en-US* | Any language code | The spoken language |

**Available voices**

| Female | Character | Male | Character |
|---|---|---|---|
| Aoede | Breezy, natural | Charon | Informative, steady |
| Kore | Firm, composed | Orus | Firm, authoritative |
| Leda | Youthful, warm | Puck | Upbeat, friendly |
| Zephyr | Bright, upbeat | Fenrir | Excitable, energetic |
| Callirrhoe | Easy-going | Iapetus | Clear, articulate |
| Erinome | Clear, measured | Umbriel | Easy-going |
| Despina | Smooth, calm | Enceladus | Breathy, soft |
| Laomedeia | Upbeat, lively | Algieba | Smooth, warm |

All voices are multilingual.

**[NEEDS INPUT]** — the *STT → Gemini → TTS* engine is offered in the dropdown but marked "coming soon" and is not implemented. Please confirm whether it should be visible to customers.

### 5.1.5 Per-question timer (Chatbot and Video Avatar)

| Option | Default | Allowed values | Effect |
|---|---|---|---|
| Enable a per-question countdown | **On** for new templates | On, Off | Adds a countdown to question turns. Off gives a relaxed conversation |
| Answer time per question (s) | 120 | Whole number | The answering window |
| Warning at (s) | 15 | Whole number | When the ring changes colour |
| Allow early submit | On | On, Off | Lets the candidate submit early |
| Auto-submit at 0 | On | On, Off | Submits whatever is typed when time runs out |
| Time follow-up questions too | On | On, Off | Whether follow-ups are also timed |
| Follow-up time (s) | 90 | Whole number, or blank | Blank means the same as the main question time |
| Add a short prep sub-timer | Off | On, Off | Locks the typing box for a brief preparation window |
| Prep time (s) | 20 | Whole number | The length of that window |
| Per-question overrides | None | Whole number per question | A different answer time for specific questions. Fixed sets only |

The countdown never runs during the greeting, the readiness question, the *Thinking…* pause, or the closing message.

### 5.1.6 Timing (Timed Q&A only)

| Option | Default | Effect |
|---|---|---|
| Prep (s) | 30 | Reading time before answering |
| Answer (s) | 120 | The answering window |
| Warning at (s) | 15 | When the warning appears |
| Allow skipping preparation | On | Lets the candidate start answering early |
| Allow early submit | On | Lets the candidate submit before time is up |
| Overall time cap (s) | No cap | An optional limit for the entire interview |

### 5.1.7 Scoring rubric

| Option | Default | Effect |
|---|---|---|
| Criterion on/off | All six on | Switched-off criteria are not scored |
| Label | See the table in [4.2.8](#428-set-up-your-scoring-guide) | The name shown on reports |
| Description | As provided | Guidance used during scoring |
| Weight | 1 for each | Relative importance. Rescaled automatically so enabled weights total 100% |
| Score scale | 100 | Fixed. Not editable |

### 5.1.8 Branding

| Option | Default | Effect |
|---|---|---|
| Company name | *TalbotIQ* | Shown on candidate screens and emails |
| Accent colour | `#0d5c3a` (dark green) | Buttons, highlights and the email header bar |
| Logo URL | Empty | Replaces the company name with your logo |
| Welcome message | *Welcome to your interview. Find a quiet spot, take a breath, and answer naturally — there are no trick questions.* | The headline on the candidate's welcome screen |

### 5.1.9 Integrity

| Option | Default | Effect |
|---|---|---|
| Enforce fullscreen | Off | Asks the candidate to stay in fullscreen; exits are recorded |
| Detect tab switching | On | Counts and warns on tab or window changes |
| Disable paste in answers | On | Blocks pasting and records the attempt |
| Disable copy | Off | Blocks copying from the answer box |
| Log integrity events | On | Shows all events on your report. Off records nothing |
| Max tab-switch warnings | 3 | The number shown in the candidate's warning counter |

## 5.2 Invitation email settings

| Option | Default | Effect |
|---|---|---|
| From address | Server default | The verified sender the email comes from |
| From name | *TalbotIQ* | The display name recipients see |
| Reply-to | Empty | Where replies go |
| Subject | Varies by kind — see below | The email subject. Supports placeholders |
| Body | Varies by kind | The message. Supports placeholders |
| Button text | *Start your interview* | The call-to-action label |
| Button colour | `#0d5c3a` | The button's background |
| Company name | *TalbotIQ* | Shown in the email header |
| Accent colour | `#0d5c3a` | The header bar |
| Logo | Empty | Replaces the company name in the header |
| Footer | *Sent via TalbotIQ.* | The small print at the bottom |
| Deadline text | Empty | Fills the `{{deadline}}` placeholder |

**Default subjects by email kind**

| Kind | Default name | Default subject | Link required? |
|---|---|---|---|
| Invite | Default invite | `Interview invitation — {{role}}` | Yes |
| Advance | Default advance | `You've advanced — {{role}} ({{round_name}})` | Yes |
| Selected | Default selection | `You've been selected — {{role}}` | No |
| Rejection | Default rejection | `Update on your {{role}} application` | No |

Colours must be valid hex codes. An invalid value falls back to the dark green default.

## 5.3 Avatar settings

Saved by **Apply to Candidate Interviews** and used by every Video Avatar interview.

| Option | Default | Limit | Effect |
|---|---|---|---|
| Replica | None | Required | The avatar face and voice |
| Persona | None | — | The behaviour profile |
| AI Interviewer Name | *Alex* | 60 characters | What the avatar calls itself |
| Conversation Name | Empty | 120 characters | A base label; the candidate's name is appended |
| Conversational Context | Empty | — | Instructions describing how the avatar behaves |
| Custom Greeting | Empty | — | The avatar's first words |
| Language | English | — | The spoken language |
| Max Call Duration | 1,800 seconds (30 min) | 60 s minimum, 7,200 s maximum | The hard limit on call length |
| Enable Recording | Off | — | Saves the session video |
| Callback URL | Empty | — | Receives event notifications |
| Fallback questions | Empty | 30 maximum | Used only when a session has no questions of its own |

Your avatar key is never shown back to you — only a masked hint.

## 5.4 Avatar studio session settings

These apply to test sessions you launch yourself.

| Option | Default | Allowed values |
|---|---|---|
| Language | English | English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Hindi, Arabic |
| Pipeline Mode | Full — audio + video | Full, Echo (test mode), No audio, Video only |
| Max Call Duration | 900 seconds (15 min) | 60 to 7,200 seconds |
| Participant Left Timeout | 60 seconds | Whole number |
| Absent Timeout | 300 seconds | Whole number |
| Enable Transcription | On | On, Off |
| Enable Recording | Off | On, Off |
| Conversation Override | Off | On, Off |
| Virtual Background | Off | On, Off |
| Background Image URL | Empty | Any image address. Shown only when Virtual Background is on |
| S3 Bucket Name / Region / Assume Role ARN | Empty | Text. Shown only when Recording is on |

## 5.5 Persona settings

| Layer | Option | Default | Allowed values |
|---|---|---|---|
| Identity | Persona Name | Empty | Any text. Required |
| Identity | Default Replica | None | Any avatar face |
| Identity | System Prompt | Empty | Up to 4,096 characters. Required |
| Identity | Context | Empty | Any text |
| LLM | Model | GPT-4o | GPT-4o, GPT-4o Mini, Claude 3.5 Sonnet, Gemini 1.5 Pro, Custom endpoint |
| LLM | Base URL / API Key | Empty | Shown only for a custom endpoint |
| LLM | Max Tokens | 1,024 | 1 to 4,096 |
| LLM | Temperature | 0.7 | 0 (predictable) to 2 (creative) |
| TTS | TTS Engine | Tavus | Tavus, Cartesia, ElevenLabs |
| TTS | API Key / External Voice ID | Empty | Shown for non-default engines |
| TTS | Speaking Speed | 1.00× | 0.5× to 2× |
| TTS | Voice Emotions | *positivity* | anger, positivity, surprise, sadness, curiosity |
| STT | STT Engine | Tavus | Tavus, Deepgram, Custom |
| STT | Pause Sensitivity | 0.5 | 0 (low) to 1 (high) |
| STT | Smart Turn Detection | On | On, Off |
| Perception | Ambient Awareness Queries | None | Any number of questions |
| Perception | Perception Model | Empty | Optional model identifier |
| VQA | Enable Camera | Off | On, Off |

## 5.6 Platform settings (Settings page)

| Option | Default | Stated effect |
|---|---|---|
| White-label Mode | Off | Remove TalbotIQ branding from candidate-facing screens |
| GDPR Auto-Purge | On | Automatically delete video and biometric data after 30 days |
| Multi-language Avatar | Off | Enable multilingual question delivery |
| Webhook URL | Empty | Receives conversation events |

**[NEEDS INPUT]** — these three toggles and the webhook field are shown in the interface, but no mechanism connecting them to any behaviour was identified. Please confirm whether they are active, and remove them from the interface or from this manual accordingly. Until confirmed, do not rely on **GDPR Auto-Purge** for any retention commitment.

Related: the Video Interview documentation states that automatic media cleanup is **not yet implemented**, while the public website describes configurable retention and purge on request. **[NEEDS INPUT]** — please confirm the actual retention behaviour before it is described to customers.

## 5.7 Settings your administrator controls

These are set once when the product is installed and are not editable in the interface. They are listed here so you know what to ask for when a feature is unavailable.

### Core

| Setting | Effect if missing |
|---|---|
| Sign-in credentials (Firebase) | Nobody can sign in; the app shows *Sign-in isn't configured yet* |
| Administrator email list | Nobody has the admin overlay |
| Data folder | Where your templates, sessions and reports are stored. On a hosted deployment this must be a permanent disk or data is lost on every update |
| Allowed website addresses | Which websites may talk to the service |

### Per feature

| Setting | Effect if missing |
|---|---|
| AI key (Gemini) | Question generation and scoring fall back to a basic length-based method; voice interviews are disabled |
| AI model / live model | Sensible defaults are used |
| Speech-to-text key (Deepgram) | No live transcription for Video Avatar or Video Interview; recordings are not transcribed |
| Emotion analysis key (Hume) | Voice prosody falls back to an AI-based analysis, or is unavailable |
| Avatar key (Tavus) | Normally entered in Settings; this is only a deployment-wide fallback |
| Live-call key (Daily) | Two-way Interviews cannot start |
| Facial analysis keys (AWS) | No facial engagement analysis |
| Mail settings (SMTP host, port, user, password, from address) | Invitations are created but not sent — dry-run mode |
| Mail provider API key (Brevo) | You must type sender addresses manually instead of picking them |
| Mail webhook secret | No delivery tracking — statuses stop at *accepted* |

### Deployment notes

- The service must run as a **single instance**. It stores data in a file, so running more than one copy would cause them to overwrite each other.
- Your administrator should back up the data file before any risky change.
- Your website address must be added to the sign-in provider's approved list, or **every login fails**.

## 5.8 Settings stored in your browser

Some preferences are stored on the computer you are using, not on your account. They do not follow you to another device.

| Setting | Where it is set |
|---|---|
| Avatar key, webhook address, default replica and persona | Settings page |
| Saved Avatar studio drafts | Avatar studio |
| Current test conversation and its questions | Avatar studio / Interview room |
| Mimic Guide conversation history | The last 20 exchanges |
| Mimic Guide voice language | The language dropdown |
| Mimic Guide auto-speak on/off | The speaker icon |

**Settings → Reset to Defaults** clears the avatar key and these local preferences after a confirmation, then reloads the page.

---

# 6. Roles & Permissions

## 6.1 How your role is decided

You choose your role when you create your account. It is stored against your account and read every time you sign in and every time you do anything in the product.

There are **two roles** — recruiter and candidate — plus one optional extra permission, administrator, that can be added to a recruiter account.

> **Important.** Because users select their own role at sign-up, anyone creating an account can choose recruiter. If your organisation needs role assignment controlled centrally, raise this with your administrator. **[NEEDS INPUT]** — please confirm the intended policy before this manual is issued externally.

## 6.2 What each role can do

| Capability | Recruiter | Candidate | Administrator |
|---|---|---|---|
| Sign in and out | ✅ | ✅ | ✅ |
| Use Mimic Guide | ✅ | ✅ | ✅ |
| See their own assigned interviews | — | ✅ | — |
| Take an interview | ✅ *(their own test sessions)* | ✅ | ✅ |
| See the Sessions list | ✅ *(own only)* | ❌ | ✅ *(all, including unclaimed legacy)* |
| Create interview sessions | ✅ | ❌ | ✅ |
| Invite candidates in bulk | ✅ | ❌ | ✅ |
| Create and edit templates | ✅ | ❌ | ✅ |
| Create and edit question sets | ✅ | ❌ | ✅ |
| Create and manage pipelines | ✅ *(own only)* | ❌ | ✅ *(all)* |
| Advance / reject candidates | ✅ *(own only)* | ❌ | ✅ *(all)* |
| View candidate reports | ✅ *(own only)* | ❌ | ✅ *(all)* |
| View analytics | ✅ *(own data only)* | ❌ | ✅ *(all data)* |
| Configure the avatar | ✅ | ❌ | ✅ |
| Manage replicas and personas | ✅ | ❌ | ✅ |
| Change Settings and API keys | ✅ | ❌ | ✅ |
| Create and edit invitation emails | ✅ *(own only)* | ❌ | ✅ *(all)* |
| Host a live two-way interview | ✅ *(own sessions)* | ❌ | ✅ |
| See their own score or report | ❌ *(not applicable)* | ❌ **Never** | ❌ |
| See another candidate's data | ❌ | ❌ | ✅ |

## 6.3 What candidates can never see

This is worth stating plainly, because it is a common question.

- Their own score, recommendation or report.
- Any feedback written about their answers.
- Upcoming questions — only the current one is ever sent to their browser.
- The ideal-answer notes attached to questions.
- Question categories.
- Any other candidate's existence or information.

## 6.4 Ownership — who sees what

Most recruiter data is scoped to the person who created it.

| Item | Who can see it |
|---|---|
| Sessions | The recruiter who created them. Administrators see all |
| Reports | The owning recruiter only. Administrators see all |
| Pipelines and their candidates | The owning recruiter. Administrators see all |
| Invitation email designs | The owning recruiter. Administrators see all |
| Analytics | Calculated only from the recruiter's own sessions. Administrators see everything |
| **Templates** | **Every recruiter sees every template** |
| **Question sets** | **Every recruiter sees every question set** |

**[NEEDS INPUT]** — templates and question sets are shared across all recruiters, unlike everything else. Please confirm whether this shared library is intentional. Until confirmed, treat templates and question sets as visible to all colleagues and avoid putting confidential information in question text or ideal-answer notes.

When you try to open something belonging to another recruiter, Mimic reports it as *not found* rather than *not allowed*. This is deliberate — it avoids confirming that another recruiter's data exists.

## 6.5 How candidates are matched to interviews

A candidate is granted access to an interview by their **email address**. To open an interview a candidate must be signed in with the exact address it was assigned to.

This means:

- Sending an invitation to the wrong address makes the interview unopenable until you re-send it.
- A candidate who signs up with a personal address cannot open an invitation sent to their work address.
- Forwarding an invitation to a colleague does not work — the link will not open for them.

## 6.6 Where the rules are enforced

Permissions are checked in two places: in the interface (which hides what you cannot use) and again on the server for every single request. Hiding a button is a convenience; the server check is what actually protects the data. You cannot bypass a permission by manipulating the page.

---

# 7. Notifications, Exports & Integrations

## 7.1 On-screen notifications

Short messages appear in the bottom-right corner and disappear after about four seconds.

| Type | Appearance | Examples |
|---|---|---|
| Success | Purple icon | *Template saved*, *Session created*, *Set saved*, *Review saved* |
| Error | Red icon | *PDF export failed*, *Retry failed*, *Connection failed* |
| Information | Plain | *That email is already in the list*, *Draft deleted* |
| Warning | ⚠️ icon | *Please stay on this tab — switching away is recorded (1/3)* |

Two indicators sit in the navigation bar:

- A **Live** badge appears while an avatar interview is running.
- An **Add API Key →** chip appears when no avatar key has been saved.

## 7.2 Emails sent to candidates

| Email | Sent when | Contains a link? |
|---|---|---|
| **Invitation** | You send invitations, or invite into round 1 of a pipeline | Yes |
| **Advance** | You advance a candidate to the next round | Yes |
| **Selected** | You advance a candidate past the final round | No |
| **Rejection** | You mark someone not advancing **and** opt in to emailing | No |
| **Test invitation** | You click *Send test to me* | Yes — to a sample link. Subject prefixed `[TEST]` |

Every email uses the same layout: a branded header, your message, the button, the locked note about which address the invitation belongs to, a plain-text copy of the link, and your footer.

## 7.3 Tracking whether emails arrived

Once your administrator has connected delivery tracking, invitation statuses update automatically.

| Status | Meaning |
|---|---|
| **accepted** | The mail service took the message for delivery |
| **delivered** | Confirmed delivered |
| **opened** | The candidate opened the email |
| **clicked** | The candidate clicked the link |
| **bounced** | The address rejected it — check for a typo |
| **spam** | Marked as spam by the recipient |
| **failed** | Blocked, invalid or deferred |

Without delivery tracking configured, statuses stop at **accepted** and never progress. Send-time success or failure and the **Retry** button still work.

## 7.4 Exports and downloads

| What | How to get it | File produced |
|---|---|---|
| Candidate report PDF | Report → **Export PDF** | `TalbotIQ-<Candidate-Name>-report.pdf` |
| Selected candidates | Pipeline board → Selected column → **Export CSV** | `<role>-selected.csv` with Name, Email, Final score |
| Avatar screening report | Results → **Download AI Report** | `TalbotIQ-Report-<session>.html` |
| A single interview link | Sessions → **Copy link**, or the copy icon in the invite results | Copied to your clipboard |
| All interview links | Invite results → **Copy all links** | Copied as one line per candidate |
| Candidate profile summary | Results → **Share Profile** | Copied to your clipboard |
| Offer recommendation | Results → **Generate Offer Rec.** → **Copy to Clipboard** | Copied to your clipboard |

**[NEEDS INPUT]** — on the avatar Results screen, **Schedule Technical Interview** shows a form and confirms *Interview scheduled* without any record being kept, and **Generate Offer Rec.** produces text only. Please confirm whether these are demonstration features. Until confirmed, do not rely on them.

## 7.5 Files you upload

| File | Where | Formats | Size limit |
|---|---|---|---|
| Candidate résumé | Interview intake screen | PDF, DOCX, TXT | 8 MB |
| Sample résumé for question generation | Generate-from-résumé dialog | **PDF only** | 10 MB |
| Candidate list | Invite wizard, Step 3 | CSV, TSV, XLSX, XLS, PDF, DOCX, TXT | 10 MB |
| Email logo | Invite email designer | Any image (PNG, JPG, SVG…) | 2 MB |
| Video answers and call recordings | Uploaded automatically | Video | 50 MB |

## 7.6 Connected services

Mimic uses a number of outside services. You do not interact with them directly, but knowing what they do helps when a feature is unavailable.

| Service | What it provides | If it is not configured |
|---|---|---|
| **Sign-in provider** | Accounts, passwords and roles | Nobody can sign in |
| **File storage** | Stores video answers, recordings and email logos | Uploads fail |
| **AI (Gemini)** | Writes questions, scores answers, powers Mimic Guide, reads sentiment | Scoring falls back to a basic length-based method and is marked approximate |
| **AI voice (Gemini Live)** | The spoken Voice interview, voice previews, Guide speech | Voice interviews are disabled |
| **Avatar service (Tavus)** | The AI video presenter, replicas and personas | Video Avatar interviews cannot start |
| **Live video (Daily)** | Two-way interview calls, the waiting lobby | Two-way interviews cannot start |
| **Speech-to-text (Deepgram)** | Live transcription and recording transcripts | No transcripts on video and avatar interviews |
| **Emotion analysis (Hume)** | Tone-of-voice analysis on the avatar Results screen | Falls back to an AI-based analysis, or is unavailable |
| **Facial analysis (AWS)** | Engagement metrics from the candidate's camera | The facial panel shows *not captured* |
| **Email (Brevo)** | Sends invitations; lists verified senders; reports delivery | Invitations are created but not sent (dry-run) |
| **Face framing (on-device)** | The framing outline before video interviews | Falls back to a plain outline and a manual *I'm ready* button. Never blocks the candidate |

The face-framing aid runs entirely on the candidate's own device. Nothing from it is uploaded, and it is **not** the facial analysis used for scoring.

## 7.7 What happens after an interview finishes

You do not need to do anything — this runs by itself.

1. The interview reaches **completed**.
2. Scoring begins automatically. The report page shows *Scoring in progress…*
3. For voice, chat and avatar interviews, the transcript is scored directly.
4. For Video Interview and Two-way, the recording or transcript is processed first.
5. Speech metrics and a sentiment read are calculated from the transcript.
6. The report appears, and the score shows in Sessions and Analytics.

For invitations, the result is also written back to the invitation record, marked as **not yet published to the candidate**. **[NEEDS INPUT]** — no interface for publishing results to candidates was identified in this product. Please confirm where publication happens.

---

# 8. Troubleshooting

Every message the product can show you, what causes it, and how to fix it.

## 8.1 Sign-in and account errors

| Message | Cause | Fix |
|---|---|---|
| **Incorrect email or password.** | The address or password does not match an account | Check for typos. If you have never signed in before, click *New here? Create an account* |
| **An account with that email already exists — sign in instead.** | You tried to create an account that already exists | Click *Already have an account? Sign in* |
| **Password should be at least 6 characters.** | The password is too short | Use six characters or more |
| **That doesn't look like a valid email address.** | The address is malformed | Check for a missing @ or a typo in the domain |
| **Too many attempts — please wait a moment and try again.** | Too many failed sign-ins in a short period | Wait a few minutes, then try again |
| **Something went wrong. Please try again.** | An unexpected sign-in problem | Try again. If it persists, contact your administrator |
| **Sign-in isn't configured yet** | The product has not been connected to its sign-in provider | Administrator task — the sign-in provider settings are missing |
| **We couldn't verify your account** | Your role could not be read | Click *Sign out and try again*. If it repeats, contact your administrator |
| **Access denied — You don't have permission to view this page.** | You opened a page your role cannot see | Click *Go to my home*. If you believe you should have access, your account may have the wrong role |
| Login fails with an *unauthorized domain* message | Your website address has not been approved with the sign-in provider | Administrator task — the domain must be added to the approved list |
| **Authentication required** | Your session expired | Reload the page and sign in again |
| **Invalid or expired authentication token** | Your session expired mid-action | Reload the page and sign in again |
| **Recruiter access required** | A candidate account tried a recruiter action | Sign in with a recruiter account |
| **Admin access required** | An action requires the administrator permission | Ask your administrator |
| **Authentication is not configured on the server** | The product cannot verify sign-ins | Administrator task — sign-in credentials are missing |

## 8.2 Candidate access errors

| Message | Cause | Fix |
|---|---|---|
| **Interview not found** | The link is wrong, or the invitation was withdrawn | Check the link in your email. If it still fails, contact your recruiter |
| **Signed in with a different account** | You are signed in with an address other than the invited one | Click *Sign out & switch account*, then sign in with the invited address |
| **This invitation was sent to a different email address. You are signed in as \<email\> — sign out, then sign in (or create your candidate account) with the email address that received the invitation.** | Same as above | Sign out and use the invited address |
| **This interview has already been completed** | You already finished this interview | No action needed. Contact your recruiter if you believe this is wrong |
| **Session not found** | The interview belongs to someone else, or does not exist | Check you are using the right link and account |
| **No interviews assigned** | Nothing is assigned to this account | Make sure you signed in with the address your invitation went to, or contact the recruiter |

## 8.3 Interview errors (candidates)

| Message | Cause | Fix |
|---|---|---|
| **Could not load the interview** | The interview could not be fetched | Reload the page. Your progress and remaining time are preserved |
| **No résumé file uploaded** | You clicked Continue without choosing a file | Choose a file, then continue |
| **Could not read meaningful text from that file** | The file is empty, scanned, or image-only | Upload a text-based PDF, DOCX or TXT rather than a scan or photo |
| **Unsupported file type — upload a PDF, DOCX, or TXT résumé.** | The file format is not accepted | Convert your résumé to PDF and try again |
| **This interview does not use résumé-based questions** | A résumé was uploaded to an interview that does not need one | No action needed — continue |
| **The interview has already started** | You tried to upload a résumé after starting | Continue with the interview |
| Hint: **Enter your full name above to continue.** | The name field has fewer than two characters | Type your full name |
| **A résumé is required before starting** | The interview needs a résumé to write your questions | Go back and upload one |
| **No questions could be generated** | Question generation failed | Contact your recruiter |
| **Interview already finished** | You tried to restart a completed interview | No action needed |
| **Skipping preparation is disabled** | Your recruiter turned this option off | Wait for the preparation time to end |
| **Early submission is disabled** | Your recruiter turned this option off | Wait for the timer to finish; your answer submits automatically |
| **Not in a preparation phase** | You clicked skip at the wrong moment | Continue answering |
| **Cannot submit during preparation** | You tried to submit before the answering window opened | Wait for the answering window |
| **No active question** / **Not the current question** / **Stale question — refresh state** | The interview has moved on since your screen last updated | The page resynchronises automatically. Continue with the question shown |
| **Stale turn — refresh** | Same as above, in a chat interview | Wait a moment; the conversation catches up |
| **Still in thinking time** | You tried to send during the preparation window | Wait, or click *Start answering now* if offered |
| **Cannot skip thinking right now** | Skipping is not available on this turn | Wait for the window to end |
| **Interview is not in progress** / **No question is awaiting an answer** | The interview finished or has not started | Reload the page |
| **Track can only be chosen before the interview begins** | You tried to change format after starting | Continue with the current format |
| **Invalid track** | An unrecognised format was requested | Reload and choose from the offered options |
| **Your answer may not have been submitted…** | A video answer failed to submit | Tell your recruiter which question was affected |
| **Microphone access is required for a voice interview.** | You blocked the microphone | Allow microphone access in your browser's address bar, then reload |
| **Could not start the microphone.** | No working microphone was found | Check your microphone is connected and not in use by another app |
| **Microphone blocked** | Permission denied | Allow access in the address bar and reload |
| **Connection problem** | The call lost its connection | Check your internet and reload |
| **Interview interrupted** | The connection dropped before the interview finished | Contact the hiring team — they can help you complete it |
| **Permission was blocked. Enable camera & mic access in your browser, then retry.** | Camera or microphone denied | Change the permission in your browser, then reload |
| **We couldn't start your camera.** | The camera is unavailable | Close other apps using the camera (video call software), then reload |
| **Camera access is blocked. Enable it in your browser, then retry.** | Camera denied during face framing | Allow camera access and reload |
| **We couldn't join your interview** | The live call could not be joined | Click *Try again*. If it repeats, contact your recruiter |
| **The interviewer has not started this interview yet.** | The recruiter has not opened the room | Keep waiting — the page retries automatically |

## 8.4 Question-generation errors

| Message | Cause | Fix |
|---|---|---|
| **Please choose a PDF file.** | A non-PDF file was selected | Convert the résumé to PDF |
| **File is too large (max 10 MB).** | The file exceeds the limit | Compress the PDF or use a smaller file |
| **Only PDF résumés are supported** | Same as above, reported by the server | Use a PDF |
| **No résumé PDF uploaded** | Generate was clicked with no file | Choose a file first |
| **Total questions must be between 1 and 25 (currently N).** | The counts add up to 0 or more than 25 | Adjust the technical and non-technical counts |
| **No Gemini API key configured. Add one in Settings or enter it in this dialog.** | No AI key is available | Enter a key in the dialog, or save one in Settings |
| **Gemini rejected the API key. Make sure it's a valid Google AI Studio key (they start with "AIza").** | The key is wrong or revoked | Check the key. Valid keys begin with `AIza` |
| **Gemini rate limit / quota exceeded. Wait a moment and try again.** | Too many requests, or your quota is used up | Wait, then retry. Check your quota with the AI provider |
| **Gemini blocked this request for safety reasons. Try a different résumé.** | The content triggered a safety filter | Try a different résumé |
| **Gemini request failed. Please try again.** | A general AI failure | Retry |
| **Gemini returned no questions. The résumé may be empty/scanned — try another file.** | Nothing readable in the file | Use a text-based PDF rather than a scan |
| **Add at least one question** | You tried to save with every question blank | Type at least one question |
| **Save failed** | The set could not be saved | Retry. Check your connection |

## 8.5 Invitation and email errors

| Message | Cause | Fix |
|---|---|---|
| **No file uploaded** | Upload was triggered with no file | Choose a file |
| **No email addresses found in that file.** | The file contains no recognisable addresses | Check the file, or add addresses manually |
| **Could not read that file.** | The file could not be opened | Check the format and size (10 MB max) |
| **That email is already in the list** | Duplicate address | No action needed |
| **A valid interview mode is required** | No format was chosen | Go back to Step 1 and pick a mode |
| **A candidate role is required** | The role is blank | Type a role in Step 1 |
| **source must be "tailor" or "set"** | No question source was chosen | Go back to Step 2 and choose one |
| **No valid candidate emails to invite** | Every address is invalid | Fix the flagged rows in Step 3 |
| **A question set must be selected** | Question sets was chosen but none picked | Select a set in Step 2 |
| **Question set not found** | The chosen set was deleted | Pick a different set |
| **Invite email is missing required token(s): {{interview_link}}** | The link placeholder was removed | Click *Insert link* in Step 4 |
| **The invite email is missing the interview link ({{interview_link}})** | Same, shown before sending | Click *Insert link* in Step 4 |
| **Add the {{interview_link}} token before testing** | You tried to send a test without the link | Click *Insert link* |
| **Could not create invites** | The batch failed | Retry. Check your connection |
| **Could not create the pipeline** | Pipeline creation failed | Check every round has a name and mode, then retry |
| **Retry failed** | Resending failed | Check the address is valid and your mail service is connected |
| **Interview not found** | The invitation record no longer exists | Create a fresh invitation |
| **Your account has no email address to send a test to** | Your account has no address | Contact your administrator |
| **Test failed** | The test email could not be sent | Check the sender address is verified |
| **Dry-run: mailer not configured (would send to …)** | The mail service is not fully connected | Administrator task. Meanwhile, copy links and send them yourself |
| **No image uploaded** | Logo upload with no file | Choose an image |
| **Logo must be an image (PNG, JPG, SVG, …)** | A non-image file was chosen | Choose an image file |
| **Logo must be under 2 MB** | The image is too large | Resize or compress it |
| **Could not upload logo** | The upload failed | Retry, or paste a public image address instead |
| Logo preview shows **This URL didn't load as an image…** | The address is not a direct image link | Use **Upload** instead. Cloud-storage share links do not work in email |
| **Could not save** / **Could not update** / **Could not duplicate** / **Could not delete** | A saved email design operation failed | Retry |
| **Invite email template not found** | The design was deleted, or belongs to another recruiter | Pick a different design |

## 8.6 Pipeline errors

| Message | Cause | Fix |
|---|---|---|
| **Round N: name is required** | A round has no name | Name every round |
| **Round N: mode "\<mode\>" is not allowed (two_way deferred)** | Two-way was chosen for a round | Choose a different format. Two-way is not available in pipelines |
| **role is required** | The pipeline has no role | Type a role in Step 1 |
| **at least one round is required** | Every round was removed | Add at least one |
| **no candidates** | The invitation had no recipients | Add candidates in Step 3 |
| **Can only advance to the next round** | You dropped a card somewhere invalid | Drag to the immediately following round, to Selected from the final round, or to Not advancing |
| **No candidates in this round meet that criteria** | No one qualified under the quick-advance rule | Lower the threshold, or wait for more interviews to be scored |
| **Candidate is not in an active round** | The candidate is already Selected or Not advancing | No action possible |
| **Candidate has not completed and been scored in the current round** | Their interview is not finished or not scored | Wait for the interview and scoring to finish |
| **Target round out of range** | The requested round does not exist | Refresh the board |
| **candidateIds and targetRoundIndex required** | An incomplete request | Refresh and retry |
| **Nothing to move back** | The candidate is in the first round, or already terminal | Move back is not available for them |
| **Current round already completed; cannot move back** | They already finished the round | Move back is no longer possible |
| **Candidate not found** | The card belongs to another pipeline or recruiter | Refresh the board |
| **Failed to move back** | The operation failed | Retry |
| **N of M email(s) failed to send** | Candidates moved but emails failed | **The moves succeeded.** Check the per-recipient reasons; resend separately if needed |
| **Failed to send** | The transition could not be completed | Retry |
| **No selected candidates to export yet** | The Selected column is empty | Select at least one candidate first |
| **Couldn't load this pipeline** | The board could not be fetched | Click *Try again* |
| **Pipeline not found** | Deleted, or belongs to another recruiter | Return to the Pipelines list |

## 8.7 Live two-way interview errors

| Message | Cause | Fix |
|---|---|---|
| **The candidate must open their interview link before you can join.** | The candidate has never opened their link | Ask them to open it, then refresh Sessions |
| **Not a two-way interview** | The session is a different format | Use the correct screen for that format |
| **This interview has already ended** | The session is finished | Open the report instead |
| **The two-way interview is not configured — set DAILY_API_KEY on the server.** | The live-call service is not connected | Administrator task |
| **Daily error (HTTP …)** | The live-call service returned an error | Retry. If it persists, contact your administrator |
| **We couldn't start the interview room** | The room could not be created or joined | Click *Try again* |
| **Could not upload the recording — finishing without it** | The recording failed to upload | The session still completes, but without a recording. Check your connection |
| **Could not finalize the session — check Sessions and try again** | Completion failed | Open Sessions and check the status |
| Stuck on **Starting the interview room…** | The connection is slow, or the call ended elsewhere | It recovers automatically. Use *Go to report* if offered |
| **Could not save the review** | The star rating and notes failed to save | Retry. Confirm you own this session |

## 8.8 Avatar and voice errors

| Message | Cause | Fix |
|---|---|---|
| **Pick a replica — candidates need a live avatar.** | Apply was clicked with no avatar chosen | Choose a replica first |
| **Add your Tavus API key in Settings first.** | No avatar key is saved | Add and save the key in Settings |
| **A replica is required — pick one on the Setup page before applying.** | Same, reported by the server | Choose a replica |
| **Could not apply the avatar settings** | Saving failed | Retry |
| **The video avatar is not configured yet — the recruiter must apply avatar settings on the Setup page.** | A candidate started a Video Avatar interview before an avatar was applied | Go to Avatar studio and click *Apply to Candidate Interviews* |
| **This interview does not use the video avatar** | Wrong format for the action | No action needed |
| **The interview has already finished** | The session is complete | Open the report |
| **No questions are configured for this interview** | No questions and no fallback questions | Check the invitation's question source, or add fallback questions in Avatar studio |
| **Tavus returned no conversation URL** | The avatar service did not return a room | Retry. Check your key and account credits |
| **Tavus API Error** panel | The avatar service rejected the request | Read the message. If it mentions credits, buy more from the avatar provider. Or click *Continue in Demo Mode* |
| **Enter a display name** | The test-session name is blank | Type a candidate name |
| **Enter a draft name** | The draft name is blank | Type a name |
| **Connection failed** | The avatar connection test failed | Check the key is correct and complete |
| **Enter your Tavus API key first** | Test was clicked with no key | Paste the key first |
| **A Gemini API key is required to preview voices** | No AI key is saved | Add one in Settings |
| **Voice preview failed — try again** | The sample could not be produced | Retry |
| **Unknown voice** | The chosen voice no longer exists | Pick a different voice |
| **Deepgram is not configured on the server** | Speech-to-text is not connected | Administrator task |
| **Deepgram token grant failed** | Speech-to-text rejected the request | Administrator task — check the key |
| **Hume is not configured on the server** | Emotion analysis is not connected | Administrator task |
| **Voice analysis unavailable: Hume rejected the job and Gemini is not configured** | Neither emotion service is available | Administrator task — configure at least one |
| **Voice-emotion analysis failed — see console for details** | The analysis job failed | Dismiss and use the other panels. The transcript and facial analysis are independent |
| **Live transcription disconnected** | The transcription connection dropped | Reload the interview page |
| **Storage bucket not configured** | File storage is not connected | Administrator task |

## 8.9 Report and analytics errors

| Message | Cause | Fix |
|---|---|---|
| **Couldn't load this report** | The report could not be fetched | Click *Try again* |
| **Scoring in progress…** | Scoring has not finished | Leave the page open — it refreshes itself |
| **Not evaluated** banner | No candidate answers were captured | Ask the candidate to retake it. Check the avatar or voice configuration |
| **Heuristic scoring** banner | No AI key is configured | Add an AI key in Settings |
| **PDF export failed** | The PDF could not be generated | Retry. Try a different browser if it repeats |
| **No questions were recorded for this interview.** | The interview captured nothing | The interview may need to be retaken |
| **No transcript was captured for this interview.** | Nothing was transcribed | Check that speech-to-text is configured, and that the candidate allowed microphone access |
| **Sentiment analysis needs a Gemini API key.** | No AI key | Add one in Settings |
| **Couldn't load analytics** | The dashboard failed to load | Retry in a moment |
| **No scored interviews yet** | Nothing has been scored | Numbers appear once interviews finish and scoring completes |
| **No scored interviews match these filters** | The filters are too narrow | Adjust or clear the filters |
| **Template for session not found** | The template was deleted | The interview still exists, but its configuration is gone |

## 8.10 Mimic Guide errors

| Message | Cause | Fix |
|---|---|---|
| **Something went wrong. Please try again.** | The assistant could not answer | Ask again |
| **I'm here to help with the TalbotIQ AI Interview Platform only…** | Your question was outside the product's scope | Ask about interviews, templates, question sets, sessions, avatar screening or results |
| **I can't reach the AI model right now — the Gemini API key looks invalid, expired, or missing.** | No working AI key | Add a valid key in Settings, or ask your administrator |
| **Couldn't play the voice for this language right now — please try again.** | Speech could not be produced | Retry, or read the answer instead |
| **Voice output needs a Gemini API key (see Settings)** | No AI key for speech | Add one in Settings |
| **Voice synthesis failed — try again** | Speech generation failed | Retry |
| **Unknown action "…"** (Autopilot) | Autopilot tried something unavailable here | Rephrase, or do it manually |
| **Missing required "…"** (Autopilot) | Autopilot needs more information | Answer the question it asks |
| Autopilot appears to do nothing when asked to continue | The current step is incomplete | Fill in the missing fields, then ask again |

## 8.11 Marketing website errors

| Message | Cause | Fix |
|---|---|---|
| **Enter your first name.** / **Enter your last name.** | The field is blank | Fill it in |
| **Enter a valid work email.** | The address is malformed | Check the address |
| **Roughly how many people do you hire a year?** | The field is blank | Enter an approximate figure |
| **Something went wrong sending that. Please try again, or email sales@talbotiq.com.** | The form could not be submitted | Retry, or email directly |
| **We couldn't find that page.** | The address does not exist | Click *Back to home* or *Explore solutions* |

## 8.12 General checks

If something is not working and no message explains why:

1. **Reload the page.** Most temporary problems clear immediately.
2. **Check you are signed in with the right account.** The initials circle in the navigation bar shows who you are.
3. **Check the service status indicators.** Settings shows whether speech-to-text, emotion analysis and facial analysis are configured.
4. **Check for a missing key.** An **Add API Key →** chip in the navigation bar means no avatar key is saved.
5. **Check whether emails are in dry-run.** If invitations are not arriving, look for the dry-run wording on the invite results screen.
6. **Try a different browser.** Camera, microphone and recording features vary between browsers.
7. **Close other apps using the camera.** Video call software often holds the camera exclusively.

---

# 9. FAQ

### About the product

**What is Mimic?**
An AI interview platform. It interviews your candidates, scores their answers against a scoring guide you define, and gives you a ranked shortlist with the evidence attached.

**Does Mimic reject candidates automatically?**
No. Mimic produces a score and a recommendation. Advancing, rejecting and overriding are all actions a recruiter takes, and each is recorded in the candidate's history.

**Do candidates know they are being interviewed by AI?**
Yes. The welcome and consent screens explain the format. Video Interview candidates must actively tick a consent box confirming they understand their responses are recorded and analysed by AI and reviewed by a human recruiter.

**Can candidates see their scores?**
No. Candidates see only a confirmation that their answers were submitted. The final screen states this explicitly.

### Setting up

**Do I need an AI key to use Mimic?**
No, but you should have one. Without it, questions come from a small generic list and scores reflect only answer length. Every affected report is clearly marked as approximate.

**Which formats need extra setup?**
Video Avatar needs an avatar key and a configured avatar. Voice needs an AI key. Two-way needs the live-call service connected by your administrator. Timed Q&A and Chatbot work with just an AI key.

**Can I try an interview myself before sending it?**
Yes. After creating a single session, click **Open as candidate ↗**. For the avatar, use **Launch Test Session** in Avatar studio.

**Where do I set the interview questions for the avatar?**
Not in Avatar studio. Questions come from the invitation — either tailored to each candidate's résumé or taken from a question set. Avatar studio only configures the presenter.

### Inviting candidates

**How many candidates can I invite at once?**
There is no stated limit on recipients. The candidate list file must be under 10 MB.

**What file formats can I upload candidates from?**
CSV, TSV, Excel (XLSX and XLS), PDF, DOCX and TXT.

**Why did the roles come out wrong after uploading a file?**
Files without a recognisable role column have every role set to the batch role from Step 1. A warning explains this. Correct individual rows in the table before sending.

**Can a candidate forward their invitation to someone else?**
No. Each link is tied to one email address. The recipient must sign in with that exact address.

**I sent an invitation to the wrong address. What now?**
Send a new invitation to the correct address. The original link cannot be reassigned.

**Why does it say emails are in dry-run?**
Your mail service is not fully connected. Invitations and links were created correctly but nothing was sent. Copy the links and send them yourself, and ask your administrator to complete the setup.

### Running interviews

**What happens if a candidate loses their connection?**
Their progress is saved. Timed interviews resume at the same question with the correct remaining time — the timing is measured by the server, so a refresh cannot extend it. Voice interviews reconnect automatically.

**Can candidates go back and change an answer?**
No. Questions are answered once, in order, and upcoming questions are never revealed early.

**What happens when the timer runs out?**
Whatever the candidate has typed is submitted automatically and the interview moves on. Their answer is marked *auto* on your report.

**Can candidates pause an interview?**
Not once a question has begun. Chatbot interviews offer a short break at the readiness question — 30, 45 or 60 seconds — before the questions start.

**Can a candidate retake an interview?**
Not through the same link. Create a new session or a new invitation.

### Reviewing results

**How is the overall score calculated?**
It is a weighted average of the criteria you switched on. Mimic calculates it, not the AI model. Weights are rescaled so the enabled criteria always total 100%.

**What do the recommendations mean?**
Strong Yes is 80 or above, Yes is 65–79, Maybe is 50–64, No is below 50.

**Why does a report say "Not evaluated"?**
No candidate answers were captured — usually because the call ended early or audio was not recorded. The zeros are placeholders, not a judgment. Ask the candidate to retake the interview.

**Is the sentiment reading based on the candidate's tone of voice?**
No. It is derived from the words in the transcript. The report states this on the panel itself.

**Why can't I see the average score on Analytics?**
Score-based panels only appear once you select a role or template. Averaging scores across different jobs is misleading, so it is deliberately prevented.

**Can I export a report?**
Yes — click **Export PDF** on any completed report.

### Permissions

**Can I change my role after signing up?**
Not from within the product. Contact your administrator.

**Can another recruiter see my candidates?**
No. Sessions, reports, pipelines and email designs are visible only to the recruiter who created them, plus administrators. **Templates and question sets, however, are shared with all recruiters** — see [6.4](#64-ownership--who-sees-what).

**Why does Mimic say "not found" when I know a session exists?**
Because it belongs to another recruiter. Mimic reports another recruiter's data as not found rather than confirming it exists.

### Mimic Guide

**What can the Mimic Guide help with?**
Anything about using the product — interviews, templates, question sets, sessions, avatar screening and results. It will not answer unrelated questions.

**What is Autopilot?**
A mode where the assistant operates the interface for you. It pauses and asks you to confirm before anything that sends an email or changes a candidate's status.

**Can I use Mimic Guide in my own language?**
Yes — 55 languages are supported for both speech and text. Answers come back in your language with an English version underneath.

---

# 10. Glossary

Terms are grouped by area. Plain-language definitions.

## Interview formats

| Term | Meaning |
|---|---|
| **Track** | The format an interview runs in. There are six |
| **Timed Q&A** | One question at a time with a preparation and answer countdown; answers submit automatically at zero |
| **Chatbot** / **Conversational** | A typed back-and-forth conversation, with optional follow-up questions |
| **Voice** | A live spoken interview with an AI interviewer |
| **Video Avatar** | An AI presenter asks the questions on video |
| **Video Interview** | The candidate answers on camera; their speech is transcribed and becomes the answer |
| **Two-way Interview** | A live video call between a real recruiter and the candidate |
| **Adaptive** / **Tailor** | Questions written for each candidate from their own résumé |
| **Fixed** | Everyone gets the same saved questions |
| **Résumé-adaptive** | Another name for adaptive — the interview reads the résumé and asks about what it claims |

## Building interviews

| Term | Meaning |
|---|---|
| **Template** | A saved recipe for how an interview runs: format, questions, timing, scoring, branding and integrity rules |
| **Question set** | A reusable, ordered list of fixed questions |
| **Fixed question** | One saved question, with optional category and ideal-answer notes |
| **Category** | A short grouping label on a question, such as *Experience* |
| **Ideal-answer notes** | A description of what a strong answer contains. Improves scoring. **Never shown to the candidate** |
| **Question source** | Whether questions are adaptive or fixed |
| **Focus topics** / **Domains** | Subjects you want the interview to emphasise |
| **Follow-up** | An extra question the interviewer asks to probe an answer |
| **Interviewer tone** | The manner the AI interviewer adopts |

## Running interviews

| Term | Meaning |
|---|---|
| **Session** | One candidate's interview — the thing you create and they take |
| **Status** | Where a session has reached: Created, System check, In progress, Completed or Expired |
| **Phase** | Whether the candidate is preparing or answering |
| **Turn** | One message in a conversation, from either the interviewer or the candidate |
| **Readiness gate** | The opening greeting that ends by asking "Are you ready to begin?". The reply is not scored |
| **Thinking indicator** | The animated dots shown while the interviewer composes its next message |
| **Draft** (candidate) | The candidate's in-progress answer, saved continuously so a refresh loses nothing |
| **Auto-submit** | Submitting whatever is typed when the timer reaches zero |
| **Barge-in** | Whether a candidate may interrupt the AI interviewer by speaking |
| **Voice phase** | What the voice interview is doing: connecting, greeting, listening, thinking, speaking, ended or error |
| **Face-fit** / **face framing** | The on-device aid that helps a candidate position their face. **Not** part of assessment |
| **Demo mode** | Running the avatar screens with no avatar configured — no video presenter |

## Scoring and results

| Term | Meaning |
|---|---|
| **KPI** / **Criterion** | One thing you score against, such as *Communication Clarity* |
| **Rubric** / **Scoring guide** | The full set of criteria and their weights |
| **Weight** | How much a criterion counts. Rescaled automatically to total 100% |
| **Overall score** | The weighted average of all enabled criteria, out of 100 |
| **Recommendation** | Strong Yes, Yes, Maybe or No, derived from the overall score |
| **Report** | The full scored result for one candidate |
| **Degraded** / **Heuristic scoring** | Scored without AI, based on answer length only. Clearly flagged |
| **Not evaluated** | No answers were captured. The zeros are placeholders, not a judgment |
| **Speech metrics** | Delivery statistics from the transcript: words, answers, filler words, vocabulary variety, reply time |
| **Filler words** | Hesitation words such as *um*, *uh*, *you know*, *I mean* |
| **Vocabulary variety** | The percentage of distinct words in what the candidate said |
| **Sentiment** | A reading of tone taken from the **words** in the transcript, not from audio |
| **Signal analysis** | The report section combining speech metrics and sentiment |
| **Coverage** (Analytics) | What share of scored interviews included a given criterion |
| **Interviewer review** | Your own 0–5 star rating and private notes on a live interview |

## Integrity

| Term | Meaning |
|---|---|
| **Integrity events** | Recorded actions such as switching tab, leaving fullscreen, or a blocked paste or copy |
| **Tab switch** | The candidate moved to another tab or window |
| **Integrity flag rate** | The share of scored interviews with at least one recorded event |

## Invitations and email

| Term | Meaning |
|---|---|
| **Invitation** | The record and email that gives one candidate access to one interview |
| **Batch** | One group of invitations sent together, with a shared reference |
| **Placeholder** / **merge variable** | Text like `{{role}}` replaced with real values when the email is sent |
| **Locked link** | `{{interview_link}}` — required and impossible to remove from invite and advance emails |
| **Dry run** | The mail service is not fully connected, so emails are prepared but not sent |
| **Verified sender** | An email address approved with your mail provider. Required to send |
| **Delivery status** | accepted, delivered, opened, clicked, bounced, spam or failed |

## Pipelines

| Term | Meaning |
|---|---|
| **Pipeline** | An ordered set of interview rounds for one role |
| **Round** | One stage of a pipeline, with its own format and questions |
| **Board** | The column view of a pipeline, showing where every candidate is |
| **Advance rule** | *Score ≥* (a threshold) or *Top N* (the highest scorers) |
| **Advanceable** | The candidate has completed and been genuinely scored, so they can move forward |
| **Round status** | Invited, In progress, Scored, Expired |
| **Selected** | The terminal column for candidates who passed the final round |
| **Not advancing** | The terminal column for candidates who will not continue |
| **Move back** | Undoing the most recent advance, while the new round is still unstarted |
| **History** | The record of every action taken on a candidate, with who, when and why |

## Avatar screening

| Term | Meaning |
|---|---|
| **Replica** | An avatar face and voice. Created with the avatar provider; takes about 15 minutes to train |
| **Persona** (avatar) | A saved behaviour profile: instructions, AI model, voice and listening settings |
| **Persona** (voice) | An interviewer character for the Voice track, with a default voice |
| **Conversational context** | The instructions telling the avatar how to behave |
| **Custom greeting** | The avatar's first spoken words |
| **Pipeline mode** | What the avatar call carries: full audio and video, echo test, no audio, or video only |
| **Ambient awareness** | Questions the avatar can consider about the candidate's environment |
| **VQA** | Whether the avatar can see and respond to what its camera shows |

## People and access

| Term | Meaning |
|---|---|
| **Recruiter** | Sets up and reviews interviews |
| **Candidate** | Takes interviews |
| **Administrator** | A recruiter with extra visibility of all data. Not a separate account type |
| **Legacy session** | An old interview created before ownership was recorded. Visible only to administrators |
| **Ownership** | Which recruiter created something. Determines who can see it |

## The assistant

| Term | Meaning |
|---|---|
| **Mimic Guide** | The built-in assistant available on every screen |
| **Autopilot** | The mode where the assistant operates the interface for you |
| **Side-effect action** | An Autopilot action that sends something or changes a candidate's status. Always requires confirmation |
| **Voice mode** | Hands-free assistant listening that submits automatically after a pause |

## Other

| Term | Meaning |
|---|---|
| **Mimic** | The product |
| **TalbotIQ** | The company that builds Mimic; also the default branding name |
| **Lead** | A demo request submitted through the public website |
| **Draft** (Avatar studio) | A saved avatar configuration you can reload |

---

# 11. Appendix

## 11.1 Keyboard shortcuts

| Where | Key | Action |
|---|---|---|
| Chatbot interview | **Enter** | Send your answer |
| Chatbot interview | **Shift + Enter** | Start a new line without sending |
| Mimic Guide | **Enter** | Send your message |
| Mimic Guide | **Shift + Enter** | New line without sending |
| Mimic Guide language list | **Escape** | Close the dropdown |
| Invite wizard, Step 3 | **Enter** | Add the typed email address |
| Invite wizard, Domains field | **Enter** | Add the typed domain |
| Avatar studio, Save Draft dialog | **Enter** | Save the draft |
| Avatar studio, Launch dialog | **Enter** | Launch the interview |
| Avatar Interview room | **Escape** | Exit fullscreen |
| Question sets | **Space / arrow keys** on a drag handle | Reorder questions by keyboard |
| Pipeline board | **Space / arrow keys** on a card handle | Move a card by keyboard |

## 11.2 Limits

### File sizes

| File | Limit |
|---|---|
| Candidate résumé (during an interview) | 8 MB |
| Sample résumé (question generation) | 10 MB |
| Candidate list | 10 MB |
| Email logo | 2 MB |
| Video answers and call recordings | 50 MB |
| Audio for emotion analysis | 25 MB |

### Content limits

| Item | Limit |
|---|---|
| Questions generated at once | 1 to 25 |
| Technical or non-technical count | 0 to 25 each |
| Candidate full name | 80 characters |
| Résumé text used | The first 20,000 characters |
| Interviewer review notes | 4,000 characters |
| Persona system prompt | 4,096 characters |
| Avatar interviewer name | 60 characters |
| Avatar conversation name | 120 characters |
| Avatar fallback questions | 30 |
| Mimic Guide conversation memory | The last 20 exchanges |
| Mimic Guide message length | 8,000 characters |
| Mimic Guide spoken text | 2,000 characters per request |
| Conversation transcript | 800 turns |

### Timing limits and defaults

| Setting | Default | Range |
|---|---|---|
| Preparation time | 30 seconds | Any whole number |
| Answer time | 120 seconds | Any whole number; minimum 10 in the single-session dialog |
| Warning threshold | 15 seconds | Any whole number |
| Follow-up time | 90 seconds | Any whole number |
| Preparation sub-timer | 20 seconds | Any whole number |
| Avatar max call duration | 30 minutes (applied config) / 15 minutes (test session) | 1 minute to 2 hours |
| Participant left timeout | 60 seconds | Any whole number |
| Absent timeout | 300 seconds | Any whole number |
| Chatbot readiness break | — | 30, 45 or 60 seconds |
| Live call room lifetime | About 4 hours | Fixed |
| Live call access token | About 3 hours | Fixed |

### Other limits

| Item | Limit |
|---|---|
| Voice interview session length | Approximately 15 minutes |
| Password | Minimum 6 characters |
| Candidate role | Minimum 2 characters |
| Candidate full name | Minimum 2 characters |
| Guide languages | 55 |
| Voice track voices | 16 |
| Voice track personas | 4 |
| Default scoring criteria | 6 |
| Top Candidates shown | 10 |

## 11.3 Supported formats

### Uploads

| Purpose | Accepted |
|---|---|
| Candidate résumé | PDF, DOCX, TXT |
| Question generation | PDF only |
| Candidate list | CSV, TSV, XLSX, XLS, PDF, DOCX, TXT |
| Email logo | Any image — PNG, JPG, SVG and others |
| Recordings | Video files |

### Downloads

| Item | Format |
|---|---|
| Candidate report | PDF |
| Selected candidates | CSV |
| Avatar screening report | HTML |

### Interview languages

- **Avatar interviews:** English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Hindi, Arabic
- **Chatbot and Voice:** set as free text on the template. Voice uses language codes such as `en-US`
- **Mimic Guide:** 55 languages, with fully localised starter prompts for English, Hindi, Marathi, Tamil, Telugu, Kannada and Malayalam

## 11.4 Status reference

### Session status

| Status | Meaning |
|---|---|
| **created** | The interview exists; the candidate has not begun |
| **system_check** | The candidate is on the readiness screen |
| **in_progress** | They are actively answering |
| **completed** | Finished. Scoring runs automatically |
| **expired** | No longer available. **[NEEDS INPUT]** — no process that sets this status was identified. Please confirm what expires a session and after how long |

### Pipeline candidate status

| Status | Meaning |
|---|---|
| **In round** | Actively in a round |
| **Selected** | Passed the final round |
| **Not advancing** | Will not continue |

### Score bands

| Band | Recommendation |
|---|---|
| 80–100 | Strong Yes |
| 65–79 | Yes |
| 50–64 | Maybe |
| 0–49 | No |

Analytics groups scores into 0–20, 21–40, 41–60, 61–80 and 81–100.

## 11.5 Open items requiring confirmation

Everything marked **[NEEDS INPUT]** in this manual, collected for convenience.

| # | Item | Section |
|---|---|---|
| 1 | Templates and question sets are visible to every recruiter, unlike all other data. Intentional? | [6.4](#64-ownership--who-sees-what) |
| 2 | Video Interview and Two-way Interview cannot be chosen on a template — invitation-only by design? | [1.3](#13-the-six-interview-formats) |
| 3 | Video Avatar is labelled "scaffold" and "Preview". What is its supported status? | [1.3](#13-the-six-interview-formats) |
| 4 | The *STT → Gemini → TTS* voice engine is offered but marked "coming soon". Should it be visible? | [5.1.4](#514-voice--persona-voice-only) |
| 5 | White-label Mode, GDPR Auto-Purge and Multi-language Avatar toggles have no identified effect | [5.6](#56-platform-settings-settings-page) |
| 6 | The Settings webhook address has no identified destination | [5.6](#56-platform-settings-settings-page) |
| 7 | Schedule Technical Interview and Generate Offer Rec. appear to keep no record | [7.4](#74-exports-and-downloads) |
| 8 | Two separate results screens exist. How should recruiters choose between them? | [3.5](#35-avatar-screening-screens) |
| 9 | The avatar Interview room, Results and Replicas screens are not on the navigation bar | [3.1](#31-the-recruiter-navigation-bar), [4.11.1](#4111-browse-avatar-faces) |
| 10 | Nothing was found that sets a session to *expired* | [11.4](#114-status-reference) |
| 11 | No consequence was found for exceeding the tab-switch warning limit | [4.2.10](#4210-set-your-integrity-rules) |
| 12 | Reports can show a video player, but the Video Interview track submits a transcript. Which flow produces video? | — |
| 13 | Results are marked "not yet published to the candidate" but no publishing interface was found | [7.7](#77-what-happens-after-an-interview-finishes) |
| 14 | Public-website statistics and compliance badges are marked as sample data awaiting replacement | [3.2](#32-public-screens-no-sign-in-needed) |
| 15 | The Mimic Guide's built-in knowledge describes a different role model from the one implemented | — |
| 16 | Two-way interviews require the candidate to open their link first. Is this the intended procedure? | [4.12.1](#4121-the-order-of-events-matters) |
| 17 | Automatic media cleanup is documented as not implemented, while retention is described elsewhere | [5.6](#56-platform-settings-settings-page) |
| 18 | Candidate email is required by the system but not marked required in the single-session dialog | [4.4](#44-creating-a-single-interview) |
| 19 | Self-selected roles at sign-up mean anyone can create a recruiter account | [6.1](#61-how-your-role-is-decided) |

---

# 12. Coverage checklist

Confirmation that every item in the source inventory is documented in this manual.

## Inventory §1 — Product overview

| Inventory item | Covered in |
|---|---|
| What the product is (Mimic / TalbotIQ) | 1.1 |
| Two product surfaces (AI Interview module, AI Avatar Screening) | 1.1, 3.4, 3.5 |
| Public marketing site | 1.1, 3.2, 4.15 |
| Who uses it — recruiters, candidates, admins, visitors | 1.2, 6.2 |
| Six interview tracks and their labels | 1.3, 5.1.1 |
| Technology and requirements | 2.1 |
| Client and API addresses, npm scripts | 5.7 *(framed as administrator setup; developer commands deliberately omitted for this audience)* |

## Inventory §2 — Roles, permissions and access control

| Inventory item | Covered in |
|---|---|
| Role model and where the role lives | 6.1 |
| Two roles plus the admin overlay | 6.1, 6.2 |
| Recruiter capabilities and gated areas | 6.2 |
| Ownership scoping (sessions, email designs, pipelines, analytics) | 6.4 |
| Templates and question sets not owner-scoped | 6.4, FAQ, Open item 1 |
| Candidate capabilities and restrictions | 6.2, 6.3 |
| Admin overlay behaviour | 6.2, 6.4 |
| Redirects and denial screens | 3.2, 8.1 |
| All server auth failure codes | 8.1 |
| Data-access rules (user, interview, storage records) | 6.4, 6.5, 7.5 |
| Documented security caveats | 6.1, Open item 19 |
| 404-not-403 no-leak behaviour | 6.4, FAQ |

## Inventory §3 — Screens and pages

| Inventory item | Covered in |
|---|---|
| Public: sign-in, access denied, marketing home, content pages, 404 | 3.2 |
| Marketing information architecture (5 areas, all sub-pages) | 3.2 |
| Placeholder content warning | 3.2, Open item 14 |
| Candidate: Your interviews | 3.3 |
| Candidate: all 13 interview screens | 3.3, 4.13 |
| Recruiter: Sessions | 3.4, 4.4 |
| Recruiter: Invite wizard | 3.4, 4.5 |
| Recruiter: Templates and Template editor | 3.4, 4.2 |
| Recruiter: Question sets | 3.4, 4.3 |
| Recruiter: Report | 3.4, 4.8 |
| Recruiter: Pipelines and Pipeline board | 3.4, 4.7 |
| Recruiter: Live interview room | 3.4, 4.12 |
| Recruiter: Analytics | 3.4, 4.9 |
| Avatar: Studio, Interview room, Results, Replicas, Personas, Settings | 3.5, 4.10, 4.11 |
| Mimic Guide overlay and all its controls | 3.6, 4.14 |
| Navigation bar contents | 3.1 |

## Inventory §4 — User actions

| Inventory item | Covered in |
|---|---|
| Sign in, sign up, sign out | 4.1 |
| Template create / duplicate / delete / save | 4.2.11 |
| Question set create / edit / reorder / duplicate / delete / save | 4.3 |
| Generate question set from résumé, with all validation | 4.3.4, 8.4 |
| Create a single session, including the avatar gate | 4.4 |
| Invite wizard Steps 1–5, all validation and gates | 4.5 |
| Round builder | 4.5 |
| Invite email designer, placeholders, locked token, test send | 4.6 |
| Saved email designs | 4.6.6 |
| Pipeline filtering, board reading | 4.7.2, 4.7.3 |
| Drag advance, quick advance, single advance | 4.7.4, 4.7.5 |
| Not advancing with opt-in rejection | 4.7.6 |
| Confirm-and-send panel and its result badges | 4.7.7 |
| Move back and its conditions | 4.7.8 |
| Candidate history | 4.7.9 |
| CSV export | 4.7.10, 7.4 |
| Open report, scoring-in-progress, score interpretation | 4.8.1–4.8.3 |
| Report detail, banners, per-question accordion | 4.8.4, 4.8.5 |
| Interviewer review | 4.8.6 |
| PDF export | 4.8.7, 7.4 |
| Analytics filters and the role/template gating rule | 4.9 |
| Avatar studio: choose, script, properties, apply, test, drafts | 4.10 |
| Demo mode and the avatar error panel | 4.10.5 |
| Replicas: browse, rename, delete, create guidance | 4.11.1–4.11.4 |
| Personas: create, edit, delete, all layers | 4.11.5, 4.11.6, 5.5 |
| Two-way: order of events, host, admit, record, controls, end | 4.12 |
| Candidate: open, choose format, welcome, intake, checks | 4.13.1–4.13.5 |
| Candidate: face framing | 4.13.6 |
| Candidate: all six track walkthroughs | 4.13.7–4.13.11 |
| Candidate: integrity warnings | 4.13.12 |
| Candidate: completion | 4.13.13 |
| Mimic Guide: ask, languages, speech, listen, Voice mode, Autopilot | 4.14 |
| Full Autopilot action list | 4.14.6 |
| Marketing demo form and ROI calculator | 4.15 |
| Complete API surface | *Deliberately omitted — internal detail, out of scope for a non-technical audience* |

## Inventory §5 — Settings and configuration

| Inventory item | Covered in |
|---|---|
| Template basics, questions, conversation | 5.1.1–5.1.3 |
| Voice and persona, all 16 voices, all 4 personas | 5.1.4, 4.2.5 |
| Per-question timer including overrides | 5.1.5 |
| Timing (Timed Q&A) | 5.1.6 |
| Scoring rubric and all six default criteria | 5.1.7, 4.2.8 |
| Branding | 5.1.8 |
| Integrity | 5.1.9 |
| Invite-email templates, all four kinds, all placeholders | 5.2, 4.6 |
| Avatar settings and all constraints | 5.3 |
| Avatar studio session settings | 5.4 |
| Persona layers | 5.5 |
| Platform toggles | 5.6 |
| All environment variables | 5.7 *(translated into plain language as "settings your administrator controls")* |
| Browser-stored settings | 5.8 |
| Deployment notes and operational constraints | 5.7 |

## Inventory §6 — Integrations, notifications, exports and files

| Inventory item | Covered in |
|---|---|
| All 11 third-party integrations | 7.6 |
| All five email types | 7.2, 4.6 |
| Email shell composition | 7.2 |
| Delivery status values and event mapping | 7.3 |
| Toasts, integrity warnings, nav indicators | 7.1 |
| All uploads with limits | 7.5, 11.2, 11.3 |
| All downloads and clipboard copies | 7.4, 11.3 |
| Server-side files (data store, preview cache) | 5.7 |
| Scoring and background processing | 7.7, 4.8.3 |
| Score calculation and recommendation thresholds | 4.8.3, 11.4 |
| Heuristic and not-evaluated messages | 4.8.5, 8.9 |
| Speech metrics and filler-word set | 4.8.4, Glossary |
| Sentiment as text-derived | 4.8.4, FAQ, Glossary |
| Result sync and publication state | 7.7, Open item 13 |

## Inventory §7 — Glossary

| Inventory item | Covered in |
|---|---|
| All ~75 domain terms | Section 10, grouped into nine themed tables |

## Inventory — Open Questions

| Inventory item | Covered in |
|---|---|
| All 19 open questions | Carried through as **[NEEDS INPUT]** at the relevant point, and collected in 11.5 |

## Requested manual structure

| Requirement | Status |
|---|---|
| 1. Introduction | ✅ Section 1 |
| 2. Getting Started | ✅ Section 2 |
| 3. Interface Overview | ✅ Section 3 |
| 4. Core Features with numbered steps | ✅ Section 4 (15 features) |
| 5. Settings & Configuration | ✅ Section 5 |
| 6. Roles & Permissions | ✅ Section 6 |
| 7. Notifications, Exports & Integrations | ✅ Section 7 |
| 8. Troubleshooting table | ✅ Section 8 (11 tables, ~180 messages) |
| 9. FAQ | ✅ Section 9 |
| 10. Glossary | ✅ Section 10 |
| 11. Appendix | ✅ Section 11 |
| Numbered steps in second person | ✅ Throughout Section 4 |
| Screenshot placeholders | ✅ 16 placed at the points a visual is needed |
| Tables for options, errors and permissions | ✅ Throughout |
| Unverified items marked **[NEEDS INPUT]** | ✅ 19 items, collected in 11.5 |

## Deliberate omissions

Two categories from the inventory are intentionally not reproduced, because the brief specifies a non-technical audience:

1. **The API endpoint reference** (inventory §4.16). This is an internal integration detail with no end-user action attached.
2. **Developer commands and file paths** (inventory §1.4, §5.9). Environment variables are covered in [5.7](#57-settings-your-administrator-controls), but reframed as "ask your administrator for X" rather than as configuration syntax.

Every user-facing behaviour, option, message and term from the inventory is documented above.
