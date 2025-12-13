# Social Scribe 🤖📝✨

**Stop manually summarizing meetings and drafting social media posts! Social Scribe leverages AI to transform your meeting transcripts into engaging follow-up emails and platform-specific social media content, ready to share.**

Social Scribe is a powerful Elixir and Phoenix LiveView application designed to connect to your calendars, automatically send an AI notetaker to your virtual meetings, provide accurate transcriptions via Recall.ai, and then utilize Google Gemini's advanced AI to draft compelling follow-up emails and social media posts through user-defined automation rules. This project was developed with significant AI assistance, as encouraged by the challenge, to rapidly build a feature-rich application.

---

## 🆕 Recent Changes & Enhancements

This section documents the major features and improvements added in the latest update (December 2025).

### 🎯 HubSpot CRM Integration (NEW)
**Complete HubSpot integration for meeting-based CRM updates**

- **HubSpot OAuth Authentication** (`lib/social_scribe/hubspot_oauth.ex`)
  - Secure OAuth 2.0 flow for HubSpot account connection
  - Token management and refresh handling
  - User settings page integration for connecting/disconnecting HubSpot accounts

- **HubSpot API Client** (`lib/social_scribe/hubspot.ex`)
  - Contact search functionality with customizable filters
  - Contact retrieval with detailed property access
  - Contact update capabilities for CRM synchronization
  - Comprehensive error handling for API failures
  - Rate limiting and retry logic

- **AI-Powered Contact Field Suggestions** (`lib/social_scribe/ai_content_generator.ex`)
  - Analyzes meeting transcripts to extract contact information
  - Suggests updates for HubSpot contact fields (company, job title, phone, etc.)
  - Provides reasoning for each suggested change
  - Filters out suggestions that match existing values

- **Interactive Contact Search Modal** (`lib/social_scribe_web/live/meeting_live/contact_search_modal_component.ex` - 550 lines)
  - Real-time contact search within HubSpot
  - Contact selection and preview
  - AI-generated field update suggestions with toggle selection
  - Bulk update functionality with success/error feedback
  - Modern, responsive UI with smooth animations

- **Meeting Details Enhancement** (`lib/social_scribe_web/live/meeting_live/show.ex` - +710 lines)
  - "Update HubSpot" button on meeting detail pages
  - Seamless integration with contact search modal
  - Real-time status updates during API operations
  - Error handling with user-friendly messages

- **Comprehensive Test Coverage** (`test/social_scribe/hubspot_test.exs` - 239 lines)
  - 19 test cases covering all HubSpot API operations
  - Mock-based testing using Mox and Tesla.Mock
  - Edge case and error scenario coverage
  - Authorization and parameter validation tests

### 📅 Calendar & Meeting Improvements

- **Enhanced Meeting Link Detection** (`lib/social_scribe/calendar_syncronizer.ex`)
  - Now checks for meeting links in **three locations**: `location`, `description`, and `hangoutLink` fields
  - **Microsoft Teams support added** - detects and extracts Teams meeting links
  - Supports Zoom, Google Meet, and Microsoft Teams platforms
  - More robust link extraction for various meeting formats

- **Calendar Event Validations** (`lib/social_scribe/calendar/calendar_event.ex`)
  - Start time must be before end time
  - Meeting duration must be between 1 minute and 24 hours
  - Prevents invalid calendar event creation

- **Meeting Time Change Detection** (`lib/social_scribe/calendar_syncronizer.ex`)
  - Detects when calendar events are rescheduled (5-minute threshold)
  - Automatically cancels and recreates Recall.ai bots for moved meetings
  - Logs time changes for audit trail
  - Prevents duplicate bot creation

- **Cascade Deletion Support** (`lib/social_scribe/bots.ex`, `lib/social_scribe/calendar.ex`)
  - Deleting a calendar event now properly cascades to associated bots
  - Prevents orphaned records in the database
  - Maintains referential integrity across tables

- **Client-Side Timezone Conversion** (`assets/js/app.js`)
  - Meeting times now display in user's local timezone
  - Automatic conversion from UTC to local time
  - Improved user experience for global teams

### 🔗 Webhook System (NEW)

- **Webhook Controller** (`lib/social_scribe_web/controllers/webhook_controller.ex` - 315 lines)
  - Handles incoming webhooks from external services
  - Secure webhook validation and authentication
  - Event processing and routing
  - Comprehensive logging for debugging

### 🔐 Authentication & User Management

- **Enhanced User Settings** (`lib/social_scribe_web/live/user_settings_live.ex`)
  - HubSpot account connection interface
  - Visual indicators for connected services
  - One-click disconnect functionality
  - Improved layout and user experience

- **Auth Controller Updates** (`lib/social_scribe_web/controllers/auth_controller.ex`)
  - HubSpot OAuth callback handling
  - Improved error handling for failed authentications
  - Session management enhancements

### 🧪 Testing Infrastructure

- **Test Helper Improvements** (`test/test_helper.exs`)
  - HubSpot mock configuration
  - Tesla Mock adapter setup for HTTP testing
  - Mox behavior definitions for all external services

- **Test Configuration** (`config/test.exs`)
  - Tesla Mock adapter enabled for test environment
  - Proper isolation of test dependencies

### 📦 Dependencies & Configuration

- **New Dependencies** (`mix.exs`)
  - `tesla` - HTTP client for API interactions
  - `nimble_options` - Schema validation for options

- **Environment Configuration**
  - `.env.example` added with all required environment variables:
  
    ```bash
    GOOGLE_CLIENT_ID=
    GOOGLE_CLIENT_SECRET=
    GOOGLE_REDIRECT_URI=
    RECALL_API_KEY=
    RECALL_REGION=
    GROQ_API_KEY=
    GROQ_MODEL=
    HUBSPOT_CLIENT_ID=
    HUBSPOT_CLIENT_SECRET=
    HUBSPOT_REDIRECT_URI=
    ```
  - HubSpot credentials configuration
  - Runtime configuration updates (`config/runtime.exs`)

### 🎨 UI/UX Enhancements

- **Platform Logos** (`lib/social_scribe_web/components/platform_logo.ex`)
  - Visual indicators for meeting platforms (Zoom, Google Meet)
  - Consistent branding across the application

- **Meeting List Improvements** (`lib/social_scribe_web/live/meeting_live/index.ex`)
  - Better formatting and layout
  - Improved loading states
  - Enhanced error messages

### 🐛 Bug Fixes & Stability

- **Accounts Module** (`lib/social_scribe/accounts.ex` - +95 lines)
  - Fixed user credential management
  - Improved token refresh logic
  - Better error handling for expired credentials

- **Meetings Module** (`lib/social_scribe/meetings.ex` - +133 lines)
  - Fixed transcript parsing issues
  - Improved participant tracking
  - Better handling of incomplete meetings

- **Recall.ai Integration** (`lib/social_scribe/recall.ex`)
  - Enhanced bot status polling
  - Improved error recovery
  - Better logging for debugging

### 📊 Statistics

**Total Changes:**
- **35 files modified**
- **3,103 lines added**
- **139 lines removed**
- **Net: +2,964 lines**

**Major Components:**
- Contact Search Modal: 550 lines
- Meeting Live Show: +710 lines
- Webhook Controller: 315 lines
- HubSpot Tests: 239 lines
- AI Content Generator: +353 lines

---

**➡️ [Live Demo](https://social-scribe.fly.dev/) ⬅️**

---

## 🌟 Key Features Implemented

* **Google Calendar Integration:**
    * Seamlessly log in with your Google Account.
    * Connect multiple Google accounts to aggregate events from all your calendars.
    * View your upcoming calendar events directly within the app's dashboard.
* **Automated Meeting Transcription with Recall.ai:**
    * Toggle a switch for any calendar event to have an AI notetaker attend.
    * The app intelligently parses event details (description, location) to find Zoom or Google Meet links.
    * Recall.ai bot joins meetings a configurable number of minutes before the start time (currently default, setting to be added to UI).
    * **Bot ID Management:** Adheres to challenge constraints by tracking individually created `bot_id`s and not using the general `/bots` endpoint.
    * **Polling for Media:** Implements a robust polling mechanism (via Oban) to check bot status and retrieve transcripts/media, as webhooks cannot be used with the shared API key.
* **AI-Powered Content Generation (Google Gemini):**
    * Automatically drafts a follow-up email summarizing key discussion points and action items from the meeting transcript.
    * **Custom Automations:** Users can create, view, and manage automation templates, defining custom prompts, target platforms (LinkedIn, Facebook), and descriptions to generate specific marketing content or other post types.
* **Social Media Integration & Posting:**
    * Securely connect LinkedIn and Facebook accounts via OAuth on the Settings page.
    * **Direct Posting:** Generated content can be posted directly to the user's connected LinkedIn profile or a user-managed Facebook Page.
* **Meeting Management & Review:**
    * View a list of past processed meetings, showing attendees, start time, and platform logo (platform logo to be enhanced).
    * Click into any past meeting to view its full transcript, the AI-generated follow-up email draft, and a list of social media posts generated by configured automations.
    * **Copy & Post Buttons:** Social media drafts are presented with a "Copy" button (implemented via JS Hooks) for easy content reuse and direct "Post" buttons for integrated platforms.
* **Modern Tech Stack & Background Processing:**
    * Built with Elixir & Phoenix LiveView for a real-time, interactive experience.
    * Utilizes Oban for robust background job processing (calendar syncing, bot status polling, AI content generation).
    * Secure credential management for all connected services using Ueberauth.

---

## App Flow

* **Login With Google and Meetins Sync:**
    ![Auth Flow](https://youtu.be/RM7YSlu5ZDg)

* **Creating Automations:**
    ![Creating Automations](https://youtu.be/V2tIKgUQYEw)

* **Meetings Recordings:**
    ![Meetings Recording](https://youtu.be/pZrLsoCfUeA)

* **Facebook Login:**
    ![Facebook Login](https://youtu.be/JRhPqCN-jeI)

* **Facebook Post:**
    ![Facebook Post](https://youtu.be/4w6zpz0Rn2o)

* **LinkedIn Login & Post:**
    ![LinkedIn Login and Post](https://youtu.be/wuD_zefGy2k)
---

## 📸 Screenshots & GIFs


* **Dashboard View:**
    ![Dashboard View](readme_assets/dashboard_view.png)


* **Automation Configuration UI:**
    ![Automation Configuration](readme_assets/edit_automation.png)

---

## 🛠 Tech Stack

* **Backend:** Elixir, Phoenix LiveView
* **Database:** PostgreSQL
* **Background Jobs:** Oban
* **Authentication:** Ueberauth (for Google, LinkedIn, Facebook OAuth)
* **Meeting Transcription:** Recall.ai API
* **AI Content Generation:** Google Gemini API (Flash models)
* **Frontend:** Tailwind CSS, Heroicons (via `tailwind.config.js`)
* **Progress Bar:** Topbar.js for page loading indication.

---

## 🚀 Getting Started

Follow these steps to get SocialScribe running on your local machine.

### Prerequisites

* Elixir
* Erlang/OTP 
* PostgreSQL
* Node.js (for Tailwind CSS asset compilation)

### Setup Instructions

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/fparadas/social_scribe.git 
    cd social_scribe
    ```

2.  **Install Dependencies & Setup Database:**
    The `mix setup` command bundles common setup tasks.
    ```bash
    mix setup
    ```
    This will typically:
    * Install Elixir dependencies (`mix deps.get`)
    * Create your database if it doesn't exist (`mix ecto.create`)
    * Run database migrations (`mix ecto.migrate`)
    * Install Node.js dependencies for assets (`cd assets && npm install && cd ..`)

3.  **Configure Environment Variables:**
    You'll need to set up several API keys and OAuth credentials.
    * Copy the example environment file (if one is provided, e.g., `.env.example`) to `.env`.
    * Edit the `.env` file (or set environment variables directly) with your actual credentials:
        * `GOOGLE_CLIENT_ID`: Your Google OAuth Client ID.
        * `GOOGLE_CLIENT_SECRET`: Your Google OAuth Client Secret.
        * `GOOGLE_REDIRECT_URI`: `"http://localhost:4000/auth/google/callback"`
        * `RECALL_API_KEY`: Your Recall.ai API Key (as provided for the challenge).
        * `GEMINI_API_KEY`: Your Google Gemini API Key.
        * `LINKEDIN_CLIENT_ID`: Your LinkedIn App Client ID.
        * `LINKEDIN_CLIENT_SECRET`: Your LinkedIn App Client Secret.
        * `LINKEDIN_REDIRECT_URI`: `"http://localhost:4000/auth/linkedin/callback"`
        * `FACEBOOK_APP_ID`: Your Facebook App ID.
        * `FACEBOOK_APP_SECRET`: Your Facebook App Secret.
        * `FACEBOOK_REDIRECT_URI`: `"http://localhost:4000/auth/facebook/callback"`

4.  **Start the Phoenix Server:**
    ```bash
    mix phx.server
    ```
    Or, to run inside IEx (Interactive Elixir):
    ```bash
    iex -S mix phx.server
    ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

---

## ⚙️ Functionality Deep Dive

* **Connect & Sync:** Users log in with Google. The "Settings" page allows connecting multiple Google accounts, plus LinkedIn and Facebook accounts. For Facebook, after initial connection, users are guided to select a Page for posting. Calendars are synced to a database to populate the dashboard with upcoming events.
* **Record & Transcribe:** On the dashboard, users toggle "Record Meeting?" for desired events. The system extracts meeting links (Zoom, Meet) and uses Recall.ai to dispatch a bot. A background poller (`BotStatusPoller`) checks for completed recordings and transcripts, saving the data to local `Meeting`, `MeetingTranscript`, and `MeetingParticipant` tables.
* **AI Content Generation:**
    * Once a meeting is processed, an `AIContentGenerationWorker` is enqueued.
    * This worker uses Google Gemini to draft a follow-up email.
    * It also processes all active "Automations" defined by the user. For each automation, it combines the meeting data with the user's `prompt_template` and calls Gemini to generate content (e.g., a LinkedIn post), saving it as an `AutomationResult`.
* **Social Posting:**
    * From the "Meeting Details" page, users can view AI-generated email drafts and posts from their automations.
    * "Copy" buttons are available.
    * "Post" buttons allow direct posting to LinkedIn (as the user) and the selected Facebook Page (as the Page).

---

## ⚠️ Known Issues & Limitations

* **Facebook Posting & App Review:**
    * Posting to Facebook is implemented via the Graph API to a user-managed Page.
    * Full functionality for all users (especially those not app administrators/developers/testers) typically requires a thorough app review process by Meta, potentially including Business Verification. This is standard for apps using Page APIs.
    * During development, posting will be most reliable for app admins to Pages they directly manage.
* **Error Handling & UI Polish:** While core paths are robustly handled, comprehensive error feedback for all API edge cases and advanced UI polish are areas for continued development beyond the initial 48-hour scope.
* **Prompt Templating for Automations:** The current automation prompt templating is basic (string replacement). A more sophisticated templating engine (e.g., EEx or a dedicated library) would be a future improvement.
* **Agenda Integration:** Currently we only sync when the calendar event has a `hangoutLink` or `location` field with a zoom or google meet link.
---

## 🛠️ CI/CD

This project includes a GitHub Actions workflow for CI/CD, as defined in `.github/workflows/ci-cd.yml`.
* **Continuous Integration:** On every push or pull request to the `main` branch, the workflow runs tests, compilation checks (with warnings as errors), and formatting checks.
* **Continuous Deployment:** On a push to the `main` branch (after tests pass), the workflow includes a step to deploy the application to Fly.io. This requires the `FLY_API_TOKEN` to be configured as a secret in the GitHub repository settings.

---

## 📚 Learn More (Phoenix Framework)

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix