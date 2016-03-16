//
//  iReSignAppDelegate.h
//  iReSign
//
//  Created by Maciej Swic on 2011-05-16.
//  Copyright (c) 2011 Maciej Swic, Licensed under the MIT License.
//  See README.md for details
//

#import <Cocoa/Cocoa.h>
#import "IRTextFieldDrag.h"

@interface iReSignAppDelegate : NSObject <NSApplicationDelegate>
{
	@private
	NSWindow *__unsafe_unretained window;
	
	NSUserDefaults *defaults;
	NSFileManager *fileManager;
	NSNotificationCenter *notificationCenter;
	
	NSString *sourcePath;
	NSString *workingPath;

	NSString *appPath;
	NSString *appName;

	NSString *codesigningResult;
	NSString *verificationResult;
	
	NSMutableArray *frameworks;
	Boolean hasFrameworks;
	
	IBOutlet IRTextFieldDrag *pathField;
	IBOutlet IRTextFieldDrag *provisioningPathField;
	IBOutlet IRTextFieldDrag *entitlementField;
	IBOutlet IRTextFieldDrag *bundleIDField;
	IBOutlet NSButton *browseButton;
	IBOutlet NSButton *provisioningBrowseButton;
	IBOutlet NSButton *entitlementBrowseButton;
	IBOutlet NSButton *resignButton;
	IBOutlet NSTextField *statusLabel;
	IBOutlet NSProgressIndicator *flurry;
	IBOutlet NSButton *changeBundleIDCheckbox;
	
	IBOutlet NSComboBox *certComboBox;
	NSMutableArray *certComboBoxItems;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;

@property (nonatomic, strong) NSString *workingPath;

- (IBAction) resign: (id) sender;

- (void) doBundleIDChange: (NSString *) newBundleID;
- (void) doITunesMetadataBundleIDChange: (NSString *) newBundleID;
- (void) doAppBundleIDChange: (NSString *) newBundleID;
- (void) changeBundleIDForFile: (NSString *) filePath bundleIDKey: (NSString *) bundleIDKey newBundleID: (NSString *) newBundleID plistOutOptions: (NSPropertyListWriteOptions) options;

- (void) doProvisioning;
- (void) checkProvisioning: (NSString *) embeddedProvisionPath;
- (void) checkApplicationIdentifiers: (NSDictionary *) embeddedProvisioning;
- (void) doEntitlementsFixing;
- (void) doEntitlementsEdit;

- (void) doCodeSigning;
- (void) signFile: (NSString*) filePath;
- (void) continueCodesigning;

- (void) doVerifySignature;

- (void) doZip;
- (void) reportSuccess: (NSString *) resignedFileName;

- (IBAction) browse: (id) sender;
- (IBAction) provisioningBrowse: (id) sender;
- (IBAction) entitlementBrowse: (id) sender;
- (IBAction) changeBundleIDPressed: (id) sender;

- (void) disableControls;
- (void) enableControls;

- (NSInteger) numberOfItemsInComboBox: (NSComboBox *) aComboBox;
- (id) comboBox: (NSComboBox *) aComboBox objectValueForItemAtIndex: (NSInteger) index;

- (void) getCerts;
- (void) parseCerts: (NSString *) certData;
- (void) checkCerts: (NSString *) output;

- (void) showAlertOfKind: (NSAlertStyle) style withTitle: (NSString *) title andMessage: (NSString *) message;

- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onTerminate: (void (^)(NSTask *)) completion;
- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onCompleteReadingOutput: (void (^)(NSString *)) output;

@end
