#!/bin/bash
# 🚀 HYBRID KUSTOMIZE BUILD SCRIPT
# Combines Environment Variables + Kustomize Replacements

set -euo pipefail

# 🎯 Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
CONFIG_TEMPLATE="${SCRIPT_DIR}/config-template.yaml"
CONFIG_OUTPUT="${SCRIPT_DIR}/config.yaml"

# 🏷️ Color Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
success() { echo -e "${GREEN}✅ $1${NC}"; }

# 📋 Help Function
show_help() {
    cat << EOF
🚀 Hybrid Kustomize Build Script

Usage: $0 [OPTIONS] [ENVIRONMENT]

OPTIONS:
    -h, --help          Show this help
    -c, --config FILE   Use specific config template
    -v, --validate      Validate only (no build)
    -d, --dry-run       Show what would be deployed
    --env-file FILE     Use specific .env file

ENVIRONMENTS:
    dev                 Development environment
    staging            Staging environment
    production         Production environment
    custom             Use custom .env configuration

EXAMPLES:
    $0 dev                    # Build for development
    $0 production             # Build for production
    $0 --env-file prod.env    # Use custom env file
    $0 --dry-run staging      # Preview staging build

ENVIRONMENT VARIABLES:
    Set in .env file or export directly:

    # Core Configuration
    ODOO_NAMESPACE=odoo-18
    DEPLOYMENT_ENV=production

    # Resources
    CPU_LIMIT=8000m
    MEMORY_LIMIT=8Gi
    DATA_STORAGE_SIZE=20Gi

    # Database
    DB_STORAGE_SIZE=64Gi
    DB_INSTANCES=2

    # Ingress
    ODOO_HOSTNAME=erp.example.com
    CERT_ISSUER=letsencrypt-production

EOF
}

# 🔧 Parse Arguments
ENVIRONMENT=""
VALIDATE_ONLY=false
DRY_RUN=false
CUSTOM_ENV_FILE=""
CUSTOM_CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --env-file)
            CUSTOM_ENV_FILE="$2"
            shift 2
            ;;
        dev|staging|production|custom)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# 🌐 Set Environment Defaults
set_environment_defaults() {
    local env="$1"

    case "$env" in
        "dev")
            export DEPLOYMENT_ENV="development"
            export ENV_TIER="dev"
            export CPU_LIMIT="${CPU_LIMIT:-2000m}"
            export MEMORY_LIMIT="${MEMORY_LIMIT:-4Gi}"
            export DATA_STORAGE_SIZE="${DATA_STORAGE_SIZE:-5Gi}"
            export DB_STORAGE_SIZE="${DB_STORAGE_SIZE:-20Gi}"
            export DB_INSTANCES="${DB_INSTANCES:-1}"
            export APP_REPLICAS="${APP_REPLICAS:-1}"
            export DEBUG_MODE="${DEBUG_MODE:-true}"
            export LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
            export CERT_ISSUER="${CERT_ISSUER:-letsencrypt-staging}"
            ;;
        "staging")
            export DEPLOYMENT_ENV="staging"
            export ENV_TIER="staging"
            export CPU_LIMIT="${CPU_LIMIT:-4000m}"
            export MEMORY_LIMIT="${MEMORY_LIMIT:-8Gi}"
            export DATA_STORAGE_SIZE="${DATA_STORAGE_SIZE:-20Gi}"
            export DB_STORAGE_SIZE="${DB_STORAGE_SIZE:-50Gi}"
            export DB_INSTANCES="${DB_INSTANCES:-2}"
            export APP_REPLICAS="${APP_REPLICAS:-2}"
            export DEBUG_MODE="${DEBUG_MODE:-false}"
            export LOG_LEVEL="${LOG_LEVEL:-INFO}"
            export CERT_ISSUER="${CERT_ISSUER:-letsencrypt-production}"
            ;;
        "production")
            export DEPLOYMENT_ENV="production"
            export ENV_TIER="prod"
            export CPU_LIMIT="${CPU_LIMIT:-8000m}"
            export MEMORY_LIMIT="${MEMORY_LIMIT:-8Gi}"
            export DATA_STORAGE_SIZE="${DATA_STORAGE_SIZE:-100Gi}"
            export DB_STORAGE_SIZE="${DB_STORAGE_SIZE:-500Gi}"
            export DB_INSTANCES="${DB_INSTANCES:-3}"
            export APP_REPLICAS="${APP_REPLICAS:-3}"
            export DEBUG_MODE="${DEBUG_MODE:-false}"
            export LOG_LEVEL="${LOG_LEVEL:-WARN}"
            export CERT_ISSUER="${CERT_ISSUER:-letsencrypt-production}"
            ;;
        *)
            warn "Unknown environment '$env', using defaults"
            ;;
    esac

    # Common defaults
    export ODOO_NAMESPACE="${ODOO_NAMESPACE:-odoo-18}"
    export IMAGE_TAG="${IMAGE_TAG:-bookworm-18.0}"
    export SUPERVISOR_TAG="${SUPERVISOR_TAG:-supervisor-18.0}"
    export STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
    export ODOO_HOSTNAME="${ODOO_HOSTNAME:-erp.odoo-shell.dev}"
}

# 📂 Load Environment Files
load_env_files() {
    # Load custom env file if specified
    if [[ -n "$CUSTOM_ENV_FILE" ]]; then
        if [[ -f "$CUSTOM_ENV_FILE" ]]; then
            info "Loading custom env file: $CUSTOM_ENV_FILE"
            set -a
            source "$CUSTOM_ENV_FILE"
            set +a
        else
            error "Custom env file not found: $CUSTOM_ENV_FILE"
        fi
    fi

    # Load default .env file
    if [[ -f "$ENV_FILE" ]]; then
        info "Loading default env file: $ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    fi

    # Set environment-specific defaults
    if [[ -n "$ENVIRONMENT" ]]; then
        set_environment_defaults "$ENVIRONMENT"
    fi
}

# 🔍 Validate Configuration
validate_config() {
    info "Validating configuration..."

    # Required variables
    local required_vars=(
        "ODOO_NAMESPACE"
        "DEPLOYMENT_ENV"
        "CPU_LIMIT"
        "MEMORY_LIMIT"
        "DATA_STORAGE_SIZE"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required environment variables: ${missing_vars[*]}"
    fi

    # Validate values
    if [[ "$DEPLOYMENT_ENV" != "development" && "$DEPLOYMENT_ENV" != "staging" && "$DEPLOYMENT_ENV" != "production" ]]; then
        error "DEPLOYMENT_ENV must be one of: development, staging, production"
    fi

    success "Configuration validation passed"
}

# 🏗️ Process Config Template
process_template() {
    local template_file="${CUSTOM_CONFIG:-$CONFIG_TEMPLATE}"

    if [[ ! -f "$template_file" ]]; then
        error "Config template not found: $template_file"
    fi

    info "Processing config template: $template_file"

    # Process template with envsubst
    if ! envsubst < "$template_file" > "$CONFIG_OUTPUT"; then
        error "Failed to process config template"
    fi

    success "Config generated: $CONFIG_OUTPUT"
}

# 🧪 Validate Generated YAML
validate_yaml() {
    info "Validating generated YAML..."

    # Check for unreplaced placeholders
    local unreplaced=$(grep -c "PLACEHOLDER_" "$CONFIG_OUTPUT" || true)
    if [[ $unreplaced -gt 0 ]]; then
        error "Found $unreplaced unreplaced PLACEHOLDER_ values in generated config"
    fi

    # Validate YAML syntax
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$CONFIG_OUTPUT" >/dev/null; then
            error "Invalid YAML syntax in generated config"
        fi
    else
        warn "yq not found, skipping YAML syntax validation"
    fi

    success "YAML validation passed"
}

# 🚀 Build with Kustomize
build_kustomize() {
    info "Building with Kustomize..."

    if ! command -v kustomize >/dev/null 2>&1; then
        error "kustomize command not found. Please install kustomize."
    fi

    # Dry run option
    if [[ "$DRY_RUN" == "true" ]]; then
        info "🔍 DRY RUN - Preview of deployment:"
        kustomize build . | head -50
        warn "This is a preview. Use without --dry-run to deploy."
        return 0
    fi

    # Build and apply
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        info "Validation mode - building without applying"
        kustomize build . > /dev/null
        success "Kustomize build validation passed"
    else
        info "Applying Kustomize configuration..."
        kustomize build . | kubectl apply -f -
        success "Deployment completed successfully"
    fi
}

# 📊 Show Deployment Status
show_status() {
    if [[ "$VALIDATE_ONLY" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    info "Deployment Status:"
    echo

    # Show pods
    kubectl get pods -n "${ODOO_NAMESPACE}" -l app="${APP_NAME:-odoo-18-app}" 2>/dev/null || true

    # Show services
    kubectl get svc -n "${ODOO_NAMESPACE}" 2>/dev/null || true

    # Show ingress
    kubectl get ingress -n "${ODOO_NAMESPACE}" 2>/dev/null || true

    echo
    success "Check status with: kubectl get pods -n ${ODOO_NAMESPACE}"
    if [[ -n "${ODOO_HOSTNAME:-}" ]]; then
        success "Access Odoo at: https://${ODOO_HOSTNAME}"
    fi
}

# 🎯 Main Function
main() {
    info "🚀 Starting Hybrid Kustomize Build"
    echo

    # Load configuration
    load_env_files

    # Validate
    validate_config

    # Process template
    process_template

    # Validate YAML
    validate_yaml

    # Build/Deploy
    build_kustomize

    # Show status
    show_status

    echo
    success "🎉 Hybrid build completed successfully!"
}

# 🏁 Script Entry Point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi