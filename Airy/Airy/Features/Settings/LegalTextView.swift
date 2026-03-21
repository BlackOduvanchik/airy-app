//
//  LegalTextView.swift
//  Airy
//
//  Scrollable legal text viewer for Privacy Policy and Terms of Use.
//

import SwiftUI

struct LegalTextView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.isEmpty {
                            Spacer().frame(height: 12)
                        } else if isHeading(line) {
                            Text(line)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                        } else if isMainTitle(line) {
                            Text(line)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                                .padding(.bottom, 4)
                        } else if isEffectiveDate(line) {
                            Text(line)
                                .font(.system(size: 13))
                                .foregroundColor(theme.textTertiary)
                                .padding(.bottom, 8)
                        } else if isBullet(line) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                                Text(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                                    .lineSpacing(3)
                            }
                            .padding(.leading, 8)
                            .padding(.vertical, 1)
                        } else if isAllCaps(line) {
                            Text(line)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(theme.textSecondary)
                                .lineSpacing(3)
                                .padding(.vertical, 2)
                        } else {
                            Text(line)
                                .font(.system(size: 14))
                                .foregroundColor(theme.textSecondary)
                                .lineSpacing(3)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Line Classification

    private func isMainTitle(_ line: String) -> Bool {
        line.hasPrefix("Privacy Policy for") || line.hasPrefix("Terms of Use for")
    }

    private func isEffectiveDate(_ line: String) -> Bool {
        line.hasPrefix("Effective date:")
    }

    private func isHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isNumber else { return false }
        return trimmed.contains(". ")
    }

    private func isBullet(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("• ")
    }

    private func isAllCaps(_ line: String) -> Bool {
        let letters = line.filter { $0.isLetter }
        return letters.count > 10 && letters == letters.uppercased()
    }
}

// MARK: - Legal Text Content

enum LegalTexts {
    static let privacyPolicy = """
Privacy Policy for Airy
Effective date: March 19, 2026

Airy respects your privacy. This Privacy Policy explains how Airy collects, uses, stores, and shares information when you use the Airy mobile application, website, and related services.

If you do not agree with this Privacy Policy, please do not use Airy.

1. who we are

Airy is operated through getairy.app.
Contact: support@getairy.app

2. information we collect

Airy is designed to minimize data collection.

a. information stored locally on your device

Airy primarily stores your app data locally on your device. This may include:
 \u{2022} manually entered transactions and subscription records
 \u{2022} screenshots or images you choose to import
 \u{2022} extracted transaction or subscription details
 \u{2022} preferences, settings, and app state
 \u{2022} locally generated analytics, summaries, or categorizations

This information is not stored on our servers as part of the core app experience.

b. sign in with apple

If you choose to sign in using Sign in with Apple, we may receive limited account information from Apple, such as:
 \u{2022} a unique Apple user identifier
 \u{2022} your name, if Apple provides it and you choose to share it
 \u{2022} your email address or Apple private relay email, if Apple provides it and you choose to share it

We use this information only to authenticate your access to the app and maintain your account-related app functionality.

c. screenshots and extracted text sent for ai analysis

If you choose to use screenshot analysis features, Airy may send selected screenshots and/or text extracted from those screenshots to OpenAI for the purpose of analyzing expenses, subscriptions, transaction details, or related financial patterns.

Airy first performs a local check on the screenshot. If the app does not detect relevant numeric content locally, the screenshot is not sent for external AI analysis and the process is cancelled.

d. subscription and purchase information

If you purchase a subscription, Apple handles the payment transaction. We do not receive your full payment card details. We may receive limited subscription status information necessary to determine whether you have an active subscription.

3. how we use information

We use information only as needed to operate and improve Airy, including to:
 \u{2022} provide the core functionality of the app
 \u{2022} authenticate users through Sign in with Apple
 \u{2022} let you manually or automatically track expenses and subscriptions
 \u{2022} analyze screenshots and extract relevant financial information
 \u{2022} determine subscription status and access to premium features
 \u{2022} respond to support requests
 \u{2022} maintain app security, stability, and fraud prevention

4. where your data is stored

Most user data is stored locally on your device.

However, when you choose to use AI-powered screenshot analysis, the screenshot and/or related extracted text may be transmitted to OpenAI for processing. We do not operate our own general cloud storage system for your financial records as part of the core Airy experience.

5. sharing of information

We do not sell your personal data.

We may share limited information only in the following cases:
 \u{2022} with Apple, for authentication and subscription-related functionality
 \u{2022} with OpenAI, only when you choose to use AI analysis features that require sending screenshots or extracted text for processing
 \u{2022} when required by law, regulation, legal process, or government request
 \u{2022} to protect rights and safety, including enforcement of our Terms of Use

6. openai processing

When you use screenshot recognition and AI analysis features, screenshots and/or text derived from them may be processed by OpenAI.

By using these features, you understand and agree that:
 \u{2022} selected screenshots or related text may be sent to OpenAI for analysis
 \u{2022} AI-generated outputs may be incomplete, inaccurate, or incorrect
 \u{2022} you remain responsible for reviewing, editing, and confirming all extracted or suggested information before relying on it

Airy attempts to minimize unnecessary external processing by first checking locally whether a screenshot appears suitable for analysis.

7. no guarantee of financial accuracy

Airy is a productivity and tracking tool. It does not provide financial, tax, accounting, legal, or investment advice.

Any analytics, categorization, subscription detection, transaction recognition, or AI-generated output is provided for convenience only. You are solely responsible for reviewing and verifying the correctness of all information before acting on it.

8. data retention

Because most data is stored locally on your device, retention generally depends on:
 \u{2022} your continued use of the app
 \u{2022} your own deletion of data from the app
 \u{2022} deletion of the app from your device
 \u{2022} your Apple account usage for sign-in related access

Data sent to OpenAI for processing may be subject to OpenAI's own retention and processing practices.

9. your choices

You may choose to:
 \u{2022} enter data manually instead of using screenshot import
 \u{2022} avoid using AI-powered analysis features
 \u{2022} manage or cancel your subscription through your Apple account settings
 \u{2022} stop using Sign in with Apple by discontinuing use of the app
 \u{2022} delete locally stored app data by deleting entries or removing the app

10. children's privacy

Airy is not directed to children. We do not knowingly collect personal information from children in violation of applicable law. If you believe that a child has provided personal information through the app, please contact us at support@getairy.app.

11. security

We take reasonable steps to protect information and to design the app with privacy in mind. However, no method of storage, transmission, or electronic processing is completely secure, and we cannot guarantee absolute security.

You are responsible for maintaining the security of your device, Apple account, and access credentials.

12. international use

If you use Airy from outside the country where the service operators or third-party providers are located, your information may be processed in other jurisdictions, including where privacy laws may differ from those in your location.

13. third-party services

Airy may rely on third-party services, including:
 \u{2022} Apple
 \u{2022} OpenAI

Your use of features connected to those services may also be subject to their policies and terms.

14. changes to this privacy policy

We may update this Privacy Policy from time to time. If we make material changes, we may update the effective date above and, where appropriate, provide notice within the app or through the website.

Your continued use of Airy after an updated Privacy Policy becomes effective means you accept the revised Privacy Policy.

15. contact

If you have any questions about this Privacy Policy, contact:

support@getairy.app
getairy.app
"""

    static let termsOfUse = """
Terms of Use for Airy
Effective date: March 19, 2026

These Terms of Use govern your use of the Airy mobile application, website, and related services.

By downloading, accessing, or using Airy, you agree to these Terms of Use. If you do not agree, do not use Airy.

1. who we are

Airy is made available through getairy.app.
Contact: support@getairy.app

2. eligibility

You may use Airy only in compliance with applicable law and these Terms.

If you are under the age required to form a binding agreement in your jurisdiction, you may use Airy only with the involvement of a parent or legal guardian.

3. the service

Airy is a personal finance and subscription tracking tool that may allow you to:
 \u{2022} manually enter financial records
 \u{2022} upload screenshots for transaction and subscription analysis
 \u{2022} receive AI-assisted categorization, recognition, and summaries
 \u{2022} manage and review recurring spending information

Airy may modify, suspend, or discontinue all or part of the service at any time, with or without notice.

4. account access

Airy may use Sign in with Apple for account authentication.

You are responsible for maintaining the security of your Apple account and device.

You are responsible for all activity occurring through your access to Airy.

5. subscriptions and billing

Airy offers paid auto-renewing subscriptions through Apple's in-app purchase system.

Current subscription options may include:
 \u{2022} Monthly subscription: $6.99
 \u{2022} Yearly subscription: $49.99

Prices may vary by country, currency, taxes, and Apple storefront.

Payment will be charged to your Apple account at confirmation of purchase. Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current billing period. Your account will be charged for renewal within 24 hours before the end of the current billing period.

You can manage or cancel your subscription in your Apple account settings.

We do not control Apple's billing systems and are not responsible for Apple's payment processing, refunds, or subscription management tools, except as required by law.

6. acceptable use

You agree not to:
 \u{2022} use Airy for unlawful, fraudulent, or misleading purposes
 \u{2022} upload content you do not have the right to use
 \u{2022} interfere with or disrupt the app or related systems
 \u{2022} attempt to reverse engineer, copy, scrape, or exploit the service except as permitted by applicable law
 \u{2022} use the app in a way that could harm us, other users, or third parties

7. screenshots, user content, and permissions

You may upload screenshots, images, and manually entered data to use Airy's features.

You represent that you have the necessary rights and permissions to provide such content and to have it processed through the app and its third-party service providers.

You remain responsible for the content you submit and for verifying the accuracy of any extracted data.

8. ai features and user responsibility

Airy may use AI tools, including OpenAI, to analyze screenshots and extract financial information.

You understand and agree that:
 \u{2022} AI output may be incomplete, inaccurate, outdated, misclassified, or otherwise incorrect
 \u{2022} categories, merchant names, dates, amounts, subscription status, and other extracted fields may be wrong
 \u{2022} Airy does not guarantee the correctness, completeness, or reliability of any AI-generated result
 \u{2022} you are solely responsible for reviewing, editing, approving, and relying on any extracted or suggested information

Airy is a convenience tool only and must not be relied upon as the sole source for financial, legal, tax, accounting, or investment decisions.

9. no financial, legal, or tax advice

Airy does not provide financial advice, legal advice, accounting advice, tax advice, or investment advice.

Any information, analytics, notifications, or insights provided by Airy are for informational and organizational purposes only.

10. intellectual property

Airy, including its design, branding, software, features, text, graphics, and related materials, is owned by or licensed to us and is protected by applicable intellectual property laws.

These Terms do not transfer any ownership rights to you. We grant you a limited, non-exclusive, non-transferable, revocable license to use Airy for your personal, lawful use in accordance with these Terms.

11. privacy

Your use of Airy is also governed by our Privacy Policy. By using Airy, you also acknowledge that you have read and understood the Privacy Policy.

12. third-party services

Airy may rely on third-party providers, including Apple and OpenAI.

We are not responsible for third-party services, their availability, or their independent acts, omissions, policies, or terms.

13. termination

We may suspend or terminate your access to Airy at any time if we reasonably believe you violated these Terms, applicable law, or used the app in a harmful or abusive manner.

You may stop using Airy at any time by deleting the app and discontinuing use of the service.

14. disclaimers

AIRY IS PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS, WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, TO THE MAXIMUM EXTENT PERMITTED BY LAW.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE DISCLAIM ALL WARRANTIES, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, ACCURACY, RELIABILITY, AND THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.

WE DO NOT WARRANT THAT AI ANALYSIS, SCREENSHOT RECOGNITION, SUBSCRIPTION DETECTION, OR ANY OTHER OUTPUT WILL BE CORRECT, COMPLETE, OR SUITABLE FOR YOUR NEEDS.

15. limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, DATA, GOODWILL, OR BUSINESS OPPORTUNITY, ARISING OUT OF OR RELATED TO YOUR USE OF AIRY.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR TOTAL LIABILITY FOR ANY CLAIM ARISING OUT OF OR RELATING TO AIRY SHALL NOT EXCEED THE GREATER OF:
 \u{2022} THE AMOUNT YOU PAID TO USE AIRY IN THE TWELVE MONTHS BEFORE THE CLAIM, OR
 \u{2022} USD $50

Some jurisdictions do not allow certain limitations, so some of the above may not apply to you.

16. indemnity

You agree to defend, indemnify, and hold harmless Airy and its operators from and against claims, liabilities, damages, judgments, losses, and expenses arising out of or related to:
 \u{2022} your use of Airy
 \u{2022} your content
 \u{2022} your violation of these Terms
 \u{2022} your violation of any law or third-party right

17. changes to these terms

We may update these Terms from time to time. If we do, we may update the effective date above and, where appropriate, provide notice through the app or website.

Your continued use of Airy after updated Terms become effective means you accept the revised Terms.

18. governing law

These Terms are governed by the laws applicable in the jurisdiction chosen by the operator of Airy, unless otherwise required by mandatory consumer protection law in your place of residence.

19. contact

If you have questions about these Terms, contact:

support@getairy.app
getairy.app
"""
}
