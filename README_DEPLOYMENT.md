# Quick Troubleshooting Guide

If `./scripts/setup-gcp.sh` doesn't run or exits immediately, check the following:

## 1. Check if gcloud is installed and configured

```bash
# Check if gcloud is installed
which gcloud

# Check if you're authenticated
gcloud auth list

# If not authenticated, login
gcloud auth login

# Check current project
gcloud config get-value project

# If no project is set, set one
gcloud config set project YOUR_PROJECT_ID

# Or create a new project
gcloud projects create YOUR_PROJECT_ID
gcloud config set project YOUR_PROJECT_ID
```

## 2. Run the script with verbose output

```bash
bash -x ./scripts/setup-gcp.sh
```

This will show you exactly where the script is failing.

## 3. Common Issues

### Issue: "No GCP project set"
**Solution**: 
```bash
gcloud config set project YOUR_PROJECT_ID
```

### Issue: "Permission denied"
**Solution**: Make sure you have the necessary permissions in your GCP project:
- Project Owner or Editor role
- Or specific permissions for: Cloud Build, Cloud Run, Cloud SQL, Storage, Secret Manager

### Issue: "APIs not enabled"
**Solution**: The script will try to enable them automatically, but if it fails:
```bash
gcloud services enable cloudbuild.googleapis.com run.googleapis.com sqladmin.googleapis.com storage-component.googleapis.com storage-api.googleapis.com secretmanager.googleapis.com
```

### Issue: Script exits silently
**Solution**: Run with debug mode:
```bash
bash -x ./scripts/setup-gcp.sh 2>&1 | tee setup.log
```

## 4. Manual Setup Alternative

If the script doesn't work, you can set up manually following the steps in `DEPLOYMENT.md`:

1. Enable APIs manually
2. Create Cloud SQL instance manually
3. Create Storage buckets manually
4. Set up secrets manually

## 5. Get Help

Check the logs:
```bash
# View script output
cat setup.log

# Check gcloud configuration
gcloud config list

# Check your permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

