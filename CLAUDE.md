# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CodePraise is a **frontend web application** that displays GitHub repository contribution analysis. It serves as a client to the CodePraise API, which performs the actual repository analysis (cloning, git blame, contribution calculations). This application handles user interactions, session management, and renders contribution reports.

**Note**: This is the frontend-only client. The backend API (which handles GitHub integration, repository cloning, and contribution analysis) is a separate service.

## Common Development Commands

### Setup

```bash
bundle install
cp config/secrets_example.yml config/secrets.yml  # Configure API_HOST and APP_HOST
```

### Testing

```bash
rake spec                    # Run unit and integration tests
rake respec                  # Continuously run tests on file changes
rake spec_accept             # Run acceptance tests (requires app and API running)
```

### Running the Application

```bash
rake run                     # Start Puma web server on port 9000
rake rerun                   # Auto-restart on file changes
rake console                 # Launch Pry console with app loaded
```

**Important**: The CodePraise API must be running (default: `http://localhost:9090`) for the app to function.

### Code Quality

```bash
rake quality:all             # Run all quality checks (rubocop + reek + flog)
rake quality:rubocop         # Code style linter
rake quality:reek            # Code smell detector
rake quality:flog            # Complexity analysis
```

### Utilities

```bash
rake new_session_secret      # Generate a new session secret for Rack::Session
```

## Architecture

This application uses **Clean Architecture** with a 3-layer structure optimized for a frontend client:

### 3-Layer Architecture

```text
PRESENTATION LAYER (View Objects + HTML Views)
    ↓
APPLICATION LAYER (Controllers, Services, Forms, Representers)
    ↓
INFRASTRUCTURE LAYER (API Gateway)
```

### Layer Responsibilities

**1. Infrastructure Layer (`app/infrastructure/`)**

Minimal layer focused on external API communication:

- `code_praise_api.rb` (`Gateway::Api`): HTTP client for CodePraise API
  - `add_project(owner, name)`: POST to add a project
  - `projects_list(list)`: GET projects by fullname list
  - `appraise(request)`: GET contribution analysis for a project folder
  - `Response`: Decorator for HTTP responses with `success?`, `processing?`, `ok?`, `added?`
- `list_request.rb` (`Value::WatchedList`): Encodes/decodes watched project lists for API queries

**2. Application Layer (`app/application/`)**

Core business logic using Dry::Transaction for service orchestration:

**Controllers (`controllers/`):**

- `app.rb`: Roda web routes
  - `GET /`: Home page with watched projects list
  - `POST /project`: Add a new project to watch list
  - `GET /project/{owner}/{name}[/folder]`: View project contribution analysis
  - `DELETE /project/{owner}/{name}`: Remove project from watch list
- `helpers.rb`: `ProjectRequestPath` helper for parsing URL paths

**Services (`services/`):**

- `AddProject`: Validates input → calls API → reifies response to OpenStruct
- `ListProjects`: Fetches watched projects from API
- `AppraiseProject`: Validates project in watch list → retrieves appraisal → handles async processing

**Forms (`forms/`):**

- `NewProject`: Dry::Validation contract for GitHub URL input

**Representers (`representers/`):**

Roar-based JSON deserializers that transform API responses into OpenStruct objects:

- `ProjectRepresenter`, `ProjectsRepresenter`: Project data
- `FolderContributionsRepresenter`, `FileContributionsRepresenter`: Contribution analysis
- `ContributorRepresenter`, `CreditShareRepresenter`: Contributor data
- `MemberRepresenter`: GitHub member info
- `HttpResponseRepresenter`: API error messages

**3. Presentation Layer (`app/presentation/`)**

**View Objects (`view_objects/`):**

- `Views::Project`: Wraps project OpenStruct for display
- `Views::ProjectsList`: Collection of projects
- `Views::ProjectFolderContributions`: Folder-level contribution display
- `Views::ProjectFileContributions`: File-level contribution display
- `Views::Contributor`: Contributor display with percentage formatting
- `Views::AppraisalProcessing`: Handles async processing state (progress bar)

**Decorators (`view_objects/decorators/`):**

- `PathPresenter`: File path display formatting
- `PercentPresenter`: Percentage value formatting

**HTML Views (`views_html/`):**

- `layout.slim`: Application layout wrapper
- `home.slim`: Home page with project submission form
- `project.slim`: Project contribution analysis display
- `flash_bar.slim`: Flash message display

**Static Assets (`assets/`, `public/`):**

- `style.css`: Application styles
- `table_row.js`: Interactive table row behavior

### Key Architectural Patterns

**Service Transaction Pattern (Dry::Transaction):**

```ruby
class AddProject
  include Dry::Transaction

  step :validate_input      # Validate form data
  step :request_project     # Call API gateway
  step :reify_project       # Transform JSON to OpenStruct
end
```

**Representer Pattern (Roar):**

```ruby
Representer::Project.new(OpenStruct.new)
  .from_json(api_response.payload)
```

**Gateway Pattern:**

- Single gateway (`Gateway::Api`) handles all API communication
- Response decorator adds semantic methods (`processing?`, `success?`)

**View Object Pattern:**

- View objects wrap OpenStruct data from API
- Add presentation logic without polluting data structures

### Data Flow

**Adding a GitHub project:**

```text
POST /project (with GitHub URL)
  ↓
Forms::NewProject validates input
  ↓
Service::AddProject transaction:
  - validate_input: Parse owner/name from URL
  - request_project: Gateway::Api.add_project() → HTTP POST to API
  - reify_project: Representer::Project.from_json() → OpenStruct
  ↓
Session cookie updated with project fullname
  ↓
Redirect to GET /project/{owner}/{name}
```

**Viewing project contributions:**

```text
GET /project/{owner}/{name}
  ↓
Service::AppraiseProject transaction:
  - validate_project: Check project in session watch list
  - retrieve_folder_appraisal: Gateway::Api.appraise() → HTTP GET
  - reify_appraisal: If not processing, parse JSON to OpenStruct
  ↓
If API returns 202 (processing):
  - Views::AppraisalProcessing shows progress state
If API returns 200:
  - Views::ProjectFolderContributions wraps contribution data
  ↓
Render project.slim template
```

## Configuration

**Environment Variables (via Figaro):**

`config/secrets.yml`:

```yaml
development:
  API_HOST: http://localhost:9090    # CodePraise API server
  APP_HOST: http://localhost:9000    # This frontend app
  SESSION_SECRET: <64-byte secret>   # Generate with `rake new_session_secret`
```

**Environments:**

- `development`: Local development
- `test`: Integration tests
- `app_test`: Acceptance tests
- `production`: Production deployment

**Key Config Files:**

- `config/environment.rb`: Figaro setup, Roda configuration
- `config/secrets.yml`: Environment-specific settings (git-ignored)
- `config.ru`: Rack application entry point
- `require_app.rb`: Layer-selective code loader (infrastructure, presentation, application)

## Testing Strategy

**Test Organization (`spec/tests/`):**

- `unit/`: Unit tests (gateway tests)
  - `codepraise_api_spec.rb`: API gateway unit tests
- `integration/services/`: Service integration tests
  - `add_project_spec.rb`: AddProject service tests
  - `list_projects_spec.rb`: ListProjects service tests
  - `appraise_project_spec.rb`: AppraiseProject service tests
- `acceptance/`: End-to-end browser tests (Watir/Selenium)
  - `home_page_spec.rb`: Home page acceptance tests
  - `project_page_spec.rb`: Project page acceptance tests
  - `pages/`: Page object classes

**Test Helpers (`spec/helpers/`):**

- `spec_helper.rb`: Common test setup
- `acceptance_helper.rb`: Browser test configuration

**Running Acceptance Tests:**

1. Start the CodePraise API server (`RACK_ENV=app_test`)
2. Start this frontend app (`rake run:test`)
3. Run `rake spec_accept`

## Working in This Codebase

**Code Location Decisions:**

- API communication → `app/infrastructure/code_praise_api.rb`
- Request/response transformation → `app/application/representers/`
- Business logic transactions → `app/application/services/`
- Form validation → `app/application/forms/`
- HTTP routes → `app/application/controllers/app.rb`
- Display formatting → `app/presentation/view_objects/`
- HTML templates → `app/presentation/views_html/*.slim`
- Static assets → `app/presentation/assets/` or `app/presentation/public/`

**Adding a New Feature:**

1. Add/update representers in `app/application/representers/` if new data shapes
2. Create/update service in `app/application/services/` for business logic
3. Add form validation in `app/application/forms/` if user input needed
4. Add controller routes in `app/application/controllers/app.rb`
5. Create view objects in `app/presentation/view_objects/`
6. Create/update templates in `app/presentation/views_html/`
7. Write tests in `spec/tests/{unit,integration,acceptance}/`

**Async Processing:**

The API may return HTTP 202 for long-running operations (e.g., cloning large repos). The `processing?` response indicates the client should poll or show a progress indicator. `Views::AppraisalProcessing` handles this UI state.

## Technology Stack

- **Web**: Roda 3.x (routing), Slim 5.x (templates), Puma 6.x (server)
- **Services**: Dry::Transaction (orchestration), Dry::Validation (forms), Dry::Monads (results)
- **Serialization**: Roar 1.x (representers), MultiJson
- **HTTP**: HTTP gem 5.x
- **Testing**: Minitest, SimpleCov, Watir 7.x, Selenium WebDriver 4.x, Page-Object 2.x
- **Quality**: RuboCop, Reek, Flog

## Related Services

This frontend requires the **CodePraise API** (`api-codepraise`) to be running. The API handles:

- GitHub API integration (fetching repository data)
- Repository cloning and storage (via background worker)
- Git blame analysis for contribution calculation
- Database persistence (SQLite/PostgreSQL)
- Redis caching for appraisal results
- Real-time progress updates via Faye websockets

**API Architecture:**

- 4-layer Web API (Domain → Infrastructure → Application → Presentation)
- Background worker (Shoryuken + AWS SQS) for async git operations
- Smart caching: caches root folder appraisals, extracts subfolders on demand
- Returns HTTP 202 when appraisal is processing, 200 when complete

**API Endpoints Used by This Frontend:**

| Endpoint                                       | Method | Purpose                    |
| ---------------------------------------------- | ------ | -------------------------- |
| `/api/v1/projects/{owner}/{name}`              | POST   | Add project to database    |
| `/api/v1/projects/{owner}/{name}[/{folder}]`   | GET    | Get contribution appraisal |
| `/api/v1/projects?list={base64}`               | GET    | Get list of projects       |

**Running Both Services Locally:**

```bash
# Terminal 1: Start the API (port 9090)
cd api-codepraise
rake run

# Terminal 2: Start the API worker (for async appraisals)
cd api-codepraise
rake worker:run:dev

# Terminal 3: Start this frontend (port 9000)
cd app-codepraise
rake run
```

See `api-codepraise/CLAUDE.md` for detailed API documentation.
