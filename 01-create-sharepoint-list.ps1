<#
.SYNOPSIS
    Creates the "FAQ List" in SharePoint Online with metadata columns and sample data.
.DESCRIPTION
    Uses PnP PowerShell to provision a SharePoint list with columns for
    Question, Answer, Category, Language, Location, Department, and LastReviewed.
    Then populates it with sample FAQ items.
.PREREQUISITES
    Install-Module -Name PnP.PowerShell -Scope CurrentUser
    Register a PnP Azure AD app or use interactive login.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,           # e.g. https://contoso.sharepoint.com/sites/FAQ

    [string]$ClientId = "",     # App Registration Client ID from 00-register-app.ps1

    [string]$Tenant = "",       # Tenant ID or hostname (e.g. contoso.onmicrosoft.com)

    [string]$ListName = "FAQ List"
)

# ── Connect ────────────────────────────────────────────────
Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan

# Derive tenant .onmicrosoft.com name from SharePoint hostname if -Tenant not provided
# e.g. mngenv168112.sharepoint.com -> mngenv168112.onmicrosoft.com
if (-not $Tenant) {
    $spHost = ([uri]$SiteUrl).Host
    $tenantName = $spHost -replace '\.sharepoint\.com$', ''
    $Tenant = "$tenantName.onmicrosoft.com"
}
Write-Host "  Tenant: $Tenant" -ForegroundColor Gray

$connectParams = @{ Url = $SiteUrl; Tenant = $Tenant }
if ($ClientId) { $connectParams['ClientId'] = $ClientId }

try {
    Connect-PnPOnline @connectParams -Interactive -ForceAuthentication
} catch {
    Write-Host "Interactive login failed, falling back to device login..." -ForegroundColor Yellow
    Connect-PnPOnline @connectParams -DeviceLogin
}

# Verify the connection actually works
try {
    $web = Get-PnPWeb -ErrorAction Stop
    Write-Host "Connected to: $($web.Title) ($($web.Url))" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Not connected to SharePoint. Check your credentials and permissions." -ForegroundColor Red
    Write-Host "Make sure you have access to: $SiteUrl" -ForegroundColor Red
    exit 1
}

# ── Create list ────────────────────────────────────────────
$existingList = Get-PnPList -Identity $ListName -ErrorAction SilentlyContinue
if ($existingList) {
    Write-Host "List '$ListName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    try {
        New-PnPList -Title $ListName -Template GenericList -ErrorAction Stop
        Write-Host "Created list '$ListName'." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to create list '$ListName': $_" -ForegroundColor Red
        exit 1
    }
}

# ── Add columns ────────────────────────────────────────────
# Question (multi-line plain text)
Add-PnPField -List $ListName -DisplayName "Question" -InternalName "Question" `
    -Type Note -AddToDefaultView -ErrorAction SilentlyContinue

# Answer (multi-line plain text)
Add-PnPField -List $ListName -DisplayName "Answer" -InternalName "Answer" `
    -Type Note -AddToDefaultView -ErrorAction SilentlyContinue

# Category (choice)
Add-PnPField -List $ListName -DisplayName "Category" -InternalName "Category" `
    -Type Choice -Choices "General","IT","HR","Finance","Facilities","Security","Onboarding" `
    -AddToDefaultView -ErrorAction SilentlyContinue

# Language (choice)
Add-PnPField -List $ListName -DisplayName "Language" -InternalName "Language" `
    -Type Choice -Choices "en","de","fr","es","it","nl" `
    -AddToDefaultView -ErrorAction SilentlyContinue

# Location (choice)
Add-PnPField -List $ListName -DisplayName "Location" -InternalName "Location" `
    -Type Choice -Choices "Global","North America","Europe","Asia Pacific","Latin America" `
    -AddToDefaultView -ErrorAction SilentlyContinue

# Department (choice)
Add-PnPField -List $ListName -DisplayName "Department" -InternalName "Department" `
    -Type Choice -Choices "IT","HR","Finance","Marketing","Sales","Engineering","Legal","Operations" `
    -AddToDefaultView -ErrorAction SilentlyContinue

# LastReviewed (date)
Add-PnPField -List $ListName -DisplayName "LastReviewed" -InternalName "LastReviewed" `
    -Type DateTime -AddToDefaultView -ErrorAction SilentlyContinue

Write-Host "Columns added." -ForegroundColor Green

# ── Sample data ────────────────────────────────────────────
$sampleItems = @(
    @{
        Title        = "VPN Access"
        Question     = "How do I connect to the company VPN?"
        Answer       = "Download the GlobalProtect client from the IT portal (https://itportal.company.com). Install it, then enter the gateway address 'vpn.company.com'. Use your corporate credentials to sign in. If you have MFA enabled, approve the push notification on your authenticator app."
        Category     = "IT"
        Language     = "en"
        Location     = "Global"
        Department   = "IT"
        LastReviewed = "2025-12-01"
    },
    @{
        Title        = "Password Reset"
        Question     = "How do I reset my corporate password?"
        Answer       = "Go to https://passwordreset.company.com and follow the self-service password reset flow. You will need to verify your identity via SMS or authenticator app. If you are locked out, contact the IT Help Desk at ext. 5555."
        Category     = "IT"
        Language     = "en"
        Location     = "Global"
        Department   = "IT"
        LastReviewed = "2025-11-15"
    },
    @{
        Title        = "Urlaubsantrag"
        Question     = "Wie beantrage ich Urlaub?"
        Answer       = "Melden Sie sich im HR-Portal an und navigieren Sie zu 'Abwesenheiten > Urlaub beantragen'. Wählen Sie den gewünschten Zeitraum und reichen Sie den Antrag ein. Ihr Vorgesetzter erhält automatisch eine Benachrichtigung zur Genehmigung. Der Mindestzeitraum für die Einreichung beträgt 2 Wochen vor Urlaubsbeginn."
        Category     = "HR"
        Language     = "de"
        Location     = "Europe"
        Department   = "HR"
        LastReviewed = "2025-10-20"
    },
    @{
        Title        = "Expense Reimbursement"
        Question     = "How do I submit an expense report?"
        Answer       = "Use the Concur app or visit concur.company.com. Create a new expense report, attach scanned receipts, select the correct expense category and cost center, then submit for manager approval. Reimbursements are processed within 10 business days after approval."
        Category     = "Finance"
        Language     = "en"
        Location     = "North America"
        Department   = "Finance"
        LastReviewed = "2026-01-05"
    },
    @{
        Title        = "Office Access Card"
        Question     = "How do I get a building access card?"
        Answer       = "Visit the reception desk on the ground floor with a valid photo ID. Fill out the access request form and your manager will receive an approval email. Once approved, your access card will be programmed within 24 hours. Temporary visitor badges are available at reception."
        Category     = "Facilities"
        Language     = "en"
        Location     = "North America"
        Department   = "Operations"
        LastReviewed = "2025-09-10"
    },
    @{
        Title        = "Demande de congé"
        Question     = "Comment puis-je demander des congés?"
        Answer       = "Connectez-vous au portail RH et accédez à 'Absences > Demande de congé'. Sélectionnez les dates souhaitées et soumettez votre demande. Votre responsable recevra une notification automatique. Le délai minimum de soumission est de 2 semaines avant le début du congé."
        Category     = "HR"
        Language     = "fr"
        Location     = "Europe"
        Department   = "HR"
        LastReviewed = "2025-11-01"
    },
    @{
        Title        = "Software Installation"
        Question     = "How do I install software on my work laptop?"
        Answer       = "Open the Company Portal app (pre-installed on all managed devices). Browse or search for the software you need and click Install. If the software is not listed, submit an IT request ticket at itportal.company.com with the software name and business justification. Non-approved software cannot be installed on managed devices."
        Category     = "IT"
        Language     = "en"
        Location     = "Global"
        Department   = "IT"
        LastReviewed = "2025-12-15"
    },
    @{
        Title        = "New Employee Onboarding"
        Question     = "What should I do on my first day?"
        Answer       = "1) Report to reception at 9:00 AM with your photo ID. 2) Collect your laptop and access card from IT. 3) Complete the onboarding checklist in the HR Portal. 4) Attend the Welcome Session at 10:30 AM in Meeting Room A. 5) Set up your email, Teams, and VPN by following the Quick Start Guide emailed to your personal address."
        Category     = "Onboarding"
        Language     = "en"
        Location     = "Global"
        Department   = "HR"
        LastReviewed = "2026-01-10"
    },
    @{
        Title        = "MFA Setup"
        Question     = "How do I set up Multi-Factor Authentication?"
        Answer       = "Go to https://aka.ms/mfasetup and sign in with your corporate account. Click 'Add method' and choose Microsoft Authenticator (recommended). Install the app on your phone, scan the QR code, and verify with a test notification. You can also add a phone number as a backup method."
        Category     = "Security"
        Language     = "en"
        Location     = "Global"
        Department   = "IT"
        LastReviewed = "2026-02-01"
    },
    @{
        Title        = "Printer Setup"
        Question     = "How do I connect to office printers?"
        Answer       = "Windows: Go to Settings > Printers & Scanners > Add a printer. The office printers should appear automatically on the network. If not, add them manually using the address \\\\printserver\\FloorXPrinter. Mac: Go to System Preferences > Printers & Scanners and click +. Contact IT if you need the printer drivers."
        Category     = "IT"
        Language     = "en"
        Location     = "North America"
        Department   = "IT"
        LastReviewed = "2025-08-20"
    },
    @{
        Title        = "Solicitud de vacaciones"
        Question     = "¿Cómo solicito vacaciones?"
        Answer       = "Ingrese al portal de RRHH y vaya a 'Ausencias > Solicitar vacaciones'. Seleccione las fechas deseadas y envíe la solicitud. Su supervisor recibirá una notificación automática para su aprobación. El plazo mínimo de solicitud es de 2 semanas antes del inicio de las vacaciones."
        Category     = "HR"
        Language     = "es"
        Location     = "Latin America"
        Department   = "HR"
        LastReviewed = "2025-10-15"
    },
    @{
        Title        = "Teams Meeting Recording"
        Question     = "Where can I find recordings of Teams meetings?"
        Answer       = "Meeting recordings are automatically saved to the meeting organizer's OneDrive (for ad-hoc meetings) or to the SharePoint site of the associated Teams channel (for channel meetings). You can find them in the meeting chat or in the Recordings folder. Recordings are retained for 120 days by default."
        Category     = "IT"
        Language     = "en"
        Location     = "Global"
        Department   = "IT"
        LastReviewed = "2026-01-20"
    },
    @{
        Title        = "Data Classification"
        Question     = "How do I classify documents according to company policy?"
        Answer       = "All documents must be classified as Public, Internal, Confidential, or Strictly Confidential. In Microsoft Office apps, use the Sensitivity toolbar button to apply a label. Emails are classified automatically based on recipients and content. If unsure, default to 'Internal' and consult the Data Classification Guide on the intranet."
        Category     = "Security"
        Language     = "en"
        Location     = "Global"
        Department   = "Legal"
        LastReviewed = "2025-11-30"
    },
    @{
        Title        = "Parking Access"
        Question     = "How do I get a parking permit for the office?"
        Answer       = "Submit a parking request through the Facilities portal at facilities.company.com. Select your office location and preferred parking zone. Monthly permits cost $50 and are deducted from payroll. Visitor parking passes can be requested by emailing facilities@company.com at least 24 hours in advance."
        Category     = "Facilities"
        Language     = "en"
        Location     = "North America"
        Department   = "Operations"
        LastReviewed = "2025-07-15"
    },
    @{
        Title        = "Budget Approval Process"
        Question     = "What is the approval process for department budgets?"
        Answer       = "Department budgets must be submitted quarterly through the Finance portal. Budgets under $10,000 require manager approval only. Budgets between $10,000-$50,000 require director approval. Budgets over $50,000 require VP approval and a business case document. Submit budget requests at least 3 weeks before the quarter start."
        Category     = "Finance"
        Language     = "en"
        Location     = "Global"
        Department   = "Finance"
        LastReviewed = "2026-02-15"
    }
)

Write-Host "Adding $($sampleItems.Count) sample items..." -ForegroundColor Cyan

# Re-establish connection in case the token expired during column creation
try {
    Get-PnPConnection | Out-Null
} catch {
    Write-Host "Connection lost. Reconnecting..." -ForegroundColor Yellow
    if ($ClientId) {
        Connect-PnPOnline -Url $SiteUrl -Tenant $Tenant -ClientId $ClientId -Interactive
    } else {
        Connect-PnPOnline -Url $SiteUrl -Tenant $Tenant -Interactive
    }
    Write-Host "Reconnected." -ForegroundColor Green
}

foreach ($item in $sampleItems) {
    $values = @{
        "Title"        = $item.Title
        "Question"     = $item.Question
        "Answer"       = $item.Answer
        "Category"     = $item.Category
        "Language"     = $item.Language
        "Location"     = $item.Location
        "Department"   = $item.Department
        "LastReviewed" = $item.LastReviewed
    }
    Add-PnPListItem -List $ListName -Values $values | Out-Null
    Write-Host "  + $($item.Title)" -ForegroundColor DarkGray
}

Write-Host "`nDone! $($sampleItems.Count) FAQ items created in '$ListName'." -ForegroundColor Green
Write-Host "Open your list at: $SiteUrl/Lists/$($ListName -replace ' ','%20')" -ForegroundColor Cyan
