# PRAX Full-Stack Template Information

This template is used by the developer subagent to create full-stack PRAX applications with React frontend and FastAPI backend.

## Template Variables

The following variables must be replaced when instantiating this template:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{APP_NAME}}` | Application name (lowercase, hyphen-separated) | `ocean-data-manager` |
| `{{APP_DESCRIPTION}}` | Brief description of the application | `Ocean data management and visualization system` |
| `{{USER_REF}}` | User reference/namespace | `h2ocean` |
| `{{MEMBER_EMAIL}}` | Developer email address | `d.johnson@oceanum.science` |

## Files Containing Variables

The following files contain template variables that need to be replaced:

1. `.oceanum-prax.yml` - All variables
2. `docker-compose.yml` - `{{APP_NAME}}`
3. `docker-compose.dev.yml` - `{{APP_NAME}}`
4. `app-spec.yml` - All variables
5. `README.md` - `{{APP_NAME}}`, `{{APP_DESCRIPTION}}`, `{{MEMBER_EMAIL}}`
6. `backend/app/core/config.py` - `{{APP_NAME}}`, `{{APP_DESCRIPTION}}`
7. `backend/.env.example` - `{{APP_NAME}}`, `{{APP_DESCRIPTION}}`
8. `frontend/package.json` - `{{APP_NAME}}`
9. `frontend/index.html` - `{{APP_NAME}}`
10. `frontend/src/App.tsx` - `{{APP_NAME}}`, `{{APP_DESCRIPTION}}`
11. `frontend/.env.development` - `{{APP_NAME}}`
12. `frontend/.env.production` - `{{APP_NAME}}`

## Questions to Ask User

When creating a new application from this template, the developer subagent should ask the following questions to gather sufficient information:

### Required Questions

1. **Application Name**
   - Question: "What would you like to name your application? (Use lowercase with hyphens, e.g., 'ocean-data-manager')"
   - Maps to: `{{APP_NAME}}`
   - Validation: Must be lowercase, can contain hyphens, no spaces or special characters

2. **Application Description**
   - Question: "Please provide a brief description of what your application will do (1-2 sentences):"
   - Maps to: `{{APP_DESCRIPTION}}`
   - Example: "A platform for managing and visualizing ocean current data"

3. **User Reference/Namespace**
   - Question: "What is your user reference or namespace? (e.g., 'h2ocean', 'datascience')"
   - Maps to: `{{USER_REF}}`
   - Note: This determines the GitLab path: oceanum/apps/{{USER_REF}}/{{APP_NAME}}

4. **Developer Email**
   - Question: "What is your email address?"
   - Maps to: `{{MEMBER_EMAIL}}`
   - Validation: Must be a valid email format

### Optional Enhancement Questions

Ask these questions to customize the app-spec.yml:

5. **Data Models**
   - Question: "What types of data will your application manage? (e.g., 'users', 'ocean readings', 'ship locations')"
   - Purpose: Update the models section in app-spec.yml
   - Default: Uses generic "Item" model if not specified

6. **Key Features**
   - Question: "What are the main features you want in your application? (e.g., 'user authentication', 'data visualization', 'file upload')"
   - Purpose: Guide the app specification and future development
   - Default: Basic CRUD operations if not specified

7. **API Endpoints Needed**
   - Question: "Besides basic create/read/update/delete, are there any specific API endpoints you need? (e.g., '/search', '/export', '/analytics')"
   - Purpose: Add to app-spec.yml API section
   - Default: Basic CRUD endpoints

### Example Question Flow

```
Agent: "I'll help you create a new full-stack PRAX application. I need to gather some information first.

What would you like to name your application? (Use lowercase with hyphens)"
User: ocean-currents-viz

Agent: "Great! Please provide a brief description of what your application will do:"
User: Visualization and analysis tool for ocean current data

Agent: "What is your user reference or namespace?"
User: h2ocean

Agent: "What is your email address?"
User: scientist@oceanum.science

Agent: "What types of data will your application manage? (Optional - press Enter to use default)"
User: ocean measurements, current vectors, temperature readings

Agent: "What are the main features you want? (Optional - press Enter for basic CRUD)"
User: data visualization, map integration, export to CSV

Agent: "Perfect! I'll create your application with these settings:
- Name: ocean-currents-viz
- Description: Visualization and analysis tool for ocean current data
- Namespace: oceanum/apps/h2ocean/ocean-currents-viz
- Features: data visualization, map integration, export to CSV

Creating your application now..."
```

## App Specification File

The `app-spec.yml` file is crucial for future development with Claude Code. It should be customized based on user responses to include:

- **Models**: Specific data types the app will manage
- **API Endpoints**: All required endpoints beyond basic CRUD
- **Frontend Features**: User interface requirements
- **Future Enhancements**: Features to add later

## Post-Creation Steps

After instantiating the template, the developer subagent should:

1. **VERIFY NAMESPACE LOCATION** - CRITICAL FIRST STEP:
   - Check if the namespace `oceanum/apps/{{USER_REF}}` exists in GitLab
   - Use GitLab MCP tool to verify: `mcp__gitlab__list_group_projects` or similar
   - If namespace doesn't exist, ask user to confirm or provide correct namespace
   - Confirm the full repository path: `oceanum/apps/{{USER_REF}}/{{APP_NAME}}`
   - DO NOT proceed with repository creation until namespace is verified

2. Replace all template variables in files listed above
3. Create/update `app-spec.yml` with user-specific requirements
4. Initialize git repository
5. Create `.env` file in backend from `.env.example`
6. Create initial commit
7. Push to GitLab repository at `oceanum/apps/{{USER_REF}}/{{APP_NAME}}`
8. Provide instructions for:
   - Running locally with docker-compose.dev.yml
   - Accessing the application
   - Making the first deployment

## Repository Location

Template should be instantiated in:
`oceanum/apps/{{USER_REF}}/{{APP_NAME}}`

Example: `oceanum/apps/h2ocean/ocean-currents-viz`

## Development Workflow Guidance

After creating the app, guide the user through:

1. **Local Development**
   ```bash
   docker-compose -f docker-compose.dev.yml up
   ```

2. **First Deployment to Test**
   ```bash
   git add .
   git commit -m "Initial commit"
   git push origin main
   ```

3. **Production Release**
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

## Using Claude Code for Feature Development

After the app is created, users can provide the `app-spec.yml` file to Claude Code along with feature requests. For example:

```
"Based on the app-spec.yml, add a search endpoint that allows filtering items by name and description"
```

Claude Code will use the specification to understand:
- The existing architecture
- Data models
- API patterns
- Code structure

This ensures consistent implementation following the established patterns.

## Template Architecture

**Frontend:**
- React 18 with TypeScript
- Vite for building and dev server
- Axios for API communication
- Nginx for production serving
- API proxy configuration for development

**Backend:**
- FastAPI with Python 3.11
- Pydantic for data validation
- Uvicorn ASGI server
- CORS middleware configured
- Structured with api/core/models separation

**Deployment:**
- Docker multi-stage builds
- docker-compose for local development
- PRAX deployment configuration
- Separate test and production stages
- Health checks configured

## Key Features

- ✅ Hot reload in development mode
- ✅ Production-optimized builds
- ✅ API documentation (FastAPI auto-generated)
- ✅ CORS configured
- ✅ Health check endpoints
- ✅ Example CRUD implementation
- ✅ TypeScript for type safety
- ✅ Pydantic for data validation
- ✅ Environment-based configuration
- ✅ Ready for PRAX deployment
