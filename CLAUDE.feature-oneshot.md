# Feature Plan: One-Shot URL Sharing

## Overview

Enable users to directly access project appraisal URLs without first adding the project. When a user visits `/project/{owner}/{name}` (via GET request), the system should automatically:

1. Add the project to the API database if needed
2. Add it to the user's watched projects list (session)
3. Display the appraisal

This enables seamless URL sharing and bookmarking of project appraisals.

## Current Architecture

```
GET /project/{owner}/{name}
    ↓
AppraiseProject service
    ↓
validate_project step
    ↓ (project in watched list?)
    ↓ NO → Failure("Please first request this project...")
    ↓ YES → retrieve_folder_appraisal → reify_appraisal → Success
```

**Current blocking validation** in [appraise_project.rb:17-22](app/application/services/appraise_project.rb#L17-L22):

```ruby
def validate_project(input)
  if input[:watched_list].include? input[:requested].project_fullname
    Success(input)
  else
    Failure('Please first request this project to be added to your list')
  end
end
```

## Proposed Architecture

```
GET /project/{owner}/{name}
    ↓
AppraiseProject service
    ↓
ensure_project step
    ↓ (project in watched list?)
    ↓ YES → continue (already_known: true)
    ↓ NO → call Gateway::Api.add_project() → continue (project_added: true)
    ↓
retrieve_folder_appraisal → reify_appraisal → Success
    ↓
Controller updates session if project_added
```

**Benefits:**
- Users can share/bookmark project URLs directly
- No friction for first-time access to a project
- Existing watched projects proceed without extra API call

## Implementation Phases

### Phase 1: Analysis & Design

- [x] Analyze current `AppraiseProject` service flow
- [x] Analyze `AddProject` service for reusable patterns
- [x] Verify `Gateway::Api.add_project` is idempotent (safe to call for existing projects)
- [x] Document decisions in this file

### Phase 2: Modify `AppraiseProject` Service

**Replace `validate_project` with `ensure_project`:**

- [ ] Rename `validate_project` → `ensure_project`
- [ ] Add logic to call `Gateway::Api.add_project` if project not in watched list
- [ ] Return `project_added: true/false` flag in output for controller
- [ ] Handle API errors gracefully (invalid repo, network issues, etc.)
- [ ] Update unit tests

### Phase 3: Update Controller

**Modify GET route to handle auto-added projects:**

- [ ] Check `project_added` flag in service result
- [ ] Update `session[:watching]` if project was auto-added
- [ ] Show appropriate flash message for auto-added projects
- [ ] Update integration tests

### Phase 4: Acceptance Testing

- [ ] Write acceptance test: direct URL access adds project automatically
- [ ] Write acceptance test: shared URL with subfolder works
- [ ] Verify existing tests still pass

### Phase 5: Documentation & Cleanup

- [ ] Update CLAUDE.md documentation if architecture changes need documenting
- [ ] Create `.claude/_archive/` directory if it doesn't exist
- [ ] Move this plan file to `.claude/_archive/CLAUDE.feature-oneshot.md`
- [ ] Remove any `@CLAUDE.feature-oneshot.md` reference from `CLAUDE.local.md` (if added)

## Discussion Points

### Open Questions

1. ⚠️ **Flash message for auto-added projects**: Should it say "Project added to your list" (same as POST) or something different like "Project added automatically"?
   - Current thinking: Use same message for consistency

2. ⚠️ **Error handling for invalid repos**: What message should users see if they visit a URL for a non-existent GitHub repo?
   - Current thinking: Let API error propagate (e.g., "Repository not found")

3. ⚠️ **Rate limiting concerns**: Could this be abused to add many projects via scripted GET requests?
   - Current thinking: Session cookie provides some protection; same risk exists with POST form

---

## Decisions Made

### Decision 1: Flash Message for Auto-Added Projects

- Use same message as POST form: "Project added to your list"
- **Rationale**: Consistent UX - the action is the same regardless of how it was triggered

### Decision 2: Error Handling for Invalid Repos

- Let API error propagate (e.g., "Repository not found")
- User is redirected to home page with error message in flash bar
- **Rationale**: API already returns sensible error messages; keeps frontend thin

### Decision 3: No Special Rate Limiting

- No additional rate limiting for auto-add via GET requests
- **Rationale**: Same risk exists with POST form; session isolation limits impact; defer to API if needed

---

## Session Log

### Session 1

- Initial discussion of one-shot URL sharing feature
- Created this planning document
- Analyzed current flow in `AppraiseProject` and `AddProject` services
- Verified `Gateway::Api.add_project` can be called directly with owner/name
- Discussed and resolved all 3 Open Questions:
  - Q1: Use same flash message as POST form ("Project added to your list")
  - Q2: Let API errors propagate; user redirected to home with error in flash bar
  - Q3: No special rate limiting needed
- **Status**: Phase 1 COMPLETE; ready for Phase 2

---

## Notes

### Commit Practices

- **Summarize changes before requesting commit permission** - provide brief summary by folder/file for user review BEFORE asking to commit
- **Separate concerns into distinct commits** - e.g., test setup changes vs feature changes
- **User is author, Claude is co-author** - use `Co-Authored-By: Claude <noreply@anthropic.com>`
- **Use conventional commit messages** - `feat:`, `fix:`, `refactor:`, `docs:`, etc.
  - `feat:` only for changes to external API/service features
  - `refactor:` for internal changes (new domain objects, infrastructure, etc.)

### Implementation Practices

- **Seek consent before moving to next phase** - summarize completed work, commit, then ask to proceed
- **Include coverage report in commits** - after successful tests, amend `coverage/.resultset.json` to coding commits

### Planning Practices

- **IMPORTANT: Pause after each question** - wait for explicit user approval before proceeding to the next question during planning discussions

---

## Quick Reference

### Key Files to Modify

| File | Change |
|------|--------|
| `app/application/services/appraise_project.rb` | Replace `validate_project` with `ensure_project` |
| `app/application/controllers/app.rb` | Handle `project_added` flag, update session |

### API Gateway Method

```ruby
Gateway::Api.new(CodePraise::App.config)
  .add_project(owner_name, project_name)
# Returns Response with .success?, .failure?, .added? (201), .payload
```

### Session Update Pattern

```ruby
session[:watching].insert(0, project.fullname).uniq!
```
