# EIDOS App Template Information

This template is used by the developer subagent to create new EIDOS based applications for the Oceanum PRAX platform.

## Template Variables

The following variables must be replaced when instantiating this template:

| Variable              | Description                                    | Example                                   |
| --------------------- | ---------------------------------------------- | ----------------------------------------- |
| `{{APP_NAME}}`        | Application name (lowercase, hyphen-separated) | `my-ocean-app`                            |
| `{{APP_DESCRIPTION}}` | Brief description of the application           | `Ocean current visualization application` |
| `{{USER_REF}}`        | User reference/namespace                       | `h2ocean`                                 |
| `{{MEMBER_EMAIL}}`    | Developer email address                        | `d.johnson@oceanum.science`               |

## Files Containing Variables

The following files contain template variables that need to be replaced:

1. `.oceanum-prax.yml` - All variables
2. `package.json` - `{{APP_NAME}}`
3. `index.html` - `{{APP_NAME}}`
4. `src/App.tsx` - `{{APP_NAME}}`, `{{APP_DESCRIPTION}}`
5. `.env.development` - `{{APP_NAME}}`
6. `.env.production` - `{{APP_NAME}}`

## Template Structure

Based on the `oceanum/apps/h2ocean/sealaska-currents` project structure.

### Key Features

- **React 18** with TypeScript and Vite
- **Multi-stage Docker build** for production optimization
- **Nginx** for serving the SPA in production
- **PRAX deployment configuration** with test and prod stages
- **Environment-based configuration** for development and production

### Deployment Pipeline

1. **Test Stage**: Auto-deploys from `main` branch commits
2. **Production Stage**: Auto-deploys from version tags (e.g., `v1.0.0`)

## Usage by Developer Subagent

When creating a new app:

1. **VERIFY NAMESPACE LOCATION** - CRITICAL FIRST STEP:
   - Check if the namespace `oceanum/apps/{{USER_REF}}` exists in GitLab
   - Use GitLab MCP tool to verify the namespace
   - If namespace doesn't exist, ask user to confirm or provide correct namespace
   - Confirm the full repository path: `oceanum/apps/{{USER_REF}}/{{APP_NAME}}`
   - DO NOT proceed with repository creation until namespace is verified

2. Copy all files from this template to the target repository
3. Replace all template variables with actual values
4. Initialize git repository if needed
5. Install npm dependencies
6. Create initial commit
7. Push to GitLab under `oceanum/apps/{{USER_REF}}/{{APP_NAME}}`

## Repository Location

Template should be instantiated in:
`oceanum/apps/{{USER_REF}}/{{APP_NAME}}`

Example: `oceanum/apps/h2ocean/my-ocean-app`
