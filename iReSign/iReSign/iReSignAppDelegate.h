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

	NSString *frameworksDirPath;
	NSString *frameworkPath;
	NSString *fileName;
	
	NSString *entitlementsResult;
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
	NSArray *getCertsResult;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;

@property (nonatomic, strong) NSString *workingPath;

- (IBAction) resign: (id) sender;

- (void) checkUnzip: (NSNotification *) notification;
- (void) checkCopy: (NSNotification *) notification;

- (BOOL) doBundleIDChange: (NSString *) newBundleID;
- (BOOL) doITunesMetadataBundleIDChange: (NSString *) newBundleID;
- (BOOL) doAppBundleIDChange: (NSString *) newBundleID;
- (BOOL) changeBundleIDForFile: (NSString *) filePath bundleIDKey: (NSString *) bundleIDKey newBundleID: (NSString *) newBundleID plistOutOptions: (NSPropertyListWriteOptions) options;

- (void) doProvisioning;
- (void) checkProvisioning: (NSNotification *) notification;
- (void) doEntitlementsFixing;
- (void) checkEntitlementsFix: (NSNotification *) notification;
- (void) doEntitlementsEdit;

- (void) doCodeSigning;
- (void) signFile: (NSString*) filePath;
- (void) checkCodesigning: (NSNotification *) notification;

- (void) doVerifySignature;
-(void) checkVerificationProcess: (NSNotification *) notification;

- (void) doZip;
- (void) checkZip: (NSNotification *) notification;

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
- (void) checkCerts: (NSNotification *) notification;

- (void) showAlertOfKind: (NSAlertStyle) style withTitle: (NSString *) title andMessage: (NSString *) message;

- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onTerminate: (SEL) selector;
- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onCompleteReadingOutput: (SEL) selector;

@end
