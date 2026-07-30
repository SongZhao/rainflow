# Rainflow Auth Email Templates

Rainflow's iPhone sign-in screen expects a one-time code, not a magic-link-only email.

Supabase Email OTP and Magic Link share the same passwordless email mechanism. The default template sends only `{{ .ConfirmationURL }}`. For Rainflow, the Magic Link template must include `{{ .Token }}` so the email contains the code the app asks for.

## Dashboard Path

In the Supabase dashboard:

1. Open the Rainflow project.
2. Go to **Authentication -> Emails**.
3. Open the **Magic Link** template.
4. Replace the subject and body with the template below.
5. Save the template.
6. Request a new code from the Rainflow app.

## Magic Link Template

Subject:

```text
{{ .Token }} is your Rainflow sign-in code
```

Body:

```html
<h2>Your Rainflow sign-in code</h2>
<p>Enter this code in Rainflow:</p>
<p style="font-size: 32px; font-weight: 700; letter-spacing: 6px;">{{ .Token }}</p>
<p>This code expires shortly and can only be used once.</p>
<p>If you did not request this code, you can ignore this email.</p>
```

## Optional Link Fallback

The app currently verifies the typed code, so the code above is the required path.
If a browser/web sign-in flow later supports magic links, add the link as a secondary fallback:

```html
<p>Or sign in from a browser:</p>
<p><a href="{{ .ConfirmationURL }}">Sign in to Rainflow</a></p>
```

Do not remove `{{ .Token }}` unless the iPhone app is changed to handle deep links or browser callback sessions.
