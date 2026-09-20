# EIDOS App Template

This is a development template for creating EIDOS applications. It provides a bootstrapped React + TypeScript + Vite application with PRAX deployment configuration for the Oceanum EIDOS platform.

## Template Variables

When using this template, replace the following placeholders:

- `{{APP_NAME}}` - The name of your application (lowercase, hyphen-separated)
- `{{APP_DESCRIPTION}}` - A brief description of your application
- `{{USER_REF}}` - Your user reference (e.g., h2ocean)
- `{{MEMBER_EMAIL}}` - Your email address

## Project Structure

```
.
├── .oceanum-prax.yml      # PRAX deployment configuration
├── Dockerfile             # Multi-stage Docker build
├── nginx.conf             # Nginx configuration for serving SPA
├── package.json           # Node.js dependencies and scripts
├── tsconfig.json          # TypeScript configuration
├── vite.config.ts         # Vite bundler configuration
├── index.html             # HTML entry point
├── .env.development       # Development environment variables
├── .env.production        # Production environment variables
├── .gitignore             # Git ignore rules
├── .dockerignore          # Docker ignore rules
└── src/
    ├── main.tsx           # Application entry point
    ├── App.tsx            # Main App component
    ├── App.css            # App component styles
    └── index.css          # Global styles
```

## Getting Started

### 1. Create New Project from Template

Replace all template variables in the following files:
- `.oceanum-prax.yml`
- `package.json`
- `index.html`
- `src/App.tsx`
- `.env.development`
- `.env.production`

### 2. Install Dependencies

```bash
npm install
```

### 3. Development

Run the development server:

```bash
npm run dev
```

The app will be available at http://localhost:3000

### 4. Build

Build for production:

```bash
npm run build
```

Build for development:

```bash
npm run build:dev
```

### 5. Preview Production Build

```bash
npm run preview
```

## PRAX Deployment

### Configuration

The `.oceanum-prax.yml` file defines the PRAX deployment configuration:

- **sources**: GitLab repository configuration
- **builds**: Docker build configuration
- **services**: Application service configuration with routing
- **stages**: Deployment stages (test and prod)

### Deployment Stages

- **test**: Deploys automatically on commits to `main` branch
- **prod**: Deploys automatically on version tags matching `v\d+.\d+.\d+` (e.g., v1.0.0)

### Creating a Release

To deploy to production:

1. Commit your changes to main
2. Create and push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Docker

### Build Docker Image

```bash
docker build -t {{APP_NAME}} .
```

### Run Docker Container

```bash
docker run -p 8080:80 {{APP_NAME}}
```

The app will be available at http://localhost:8080

## Environment Variables

Environment variables are defined in `.env.development` and `.env.production`:

- `VITE_APP_TITLE`: Application title
- `VITE_API_URL`: API endpoint URL

Access in code using `import.meta.env.VITE_*`:

```typescript
const apiUrl = import.meta.env.VITE_API_URL;
```

## Customization

### Adding Dependencies

```bash
npm install package-name
```

### Adding Development Dependencies

```bash
npm install -D package-name
```

### Modifying Nginx Configuration

Edit `nginx.conf` to customize server behavior, caching rules, or add proxy configurations.

### TypeScript Configuration

Modify `tsconfig.json` to adjust TypeScript compiler options.

## Technology Stack

- **React 18**: UI framework
- **TypeScript**: Type-safe JavaScript
- **Vite**: Fast build tool and dev server
- **Nginx**: Production web server
- **Docker**: Containerization
- **PRAX**: Deployment orchestration

## Project Guidelines

- Follow React best practices and hooks patterns
- Use TypeScript for type safety
- Keep components small and focused
- Write meaningful commit messages
- Use semantic versioning for releases

## Support

For PRAX deployment issues, contact the Oceanum team.
For application issues, refer to the project's issue tracker.
