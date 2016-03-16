//
//  iReSignAppDelegate.m
//  iReSign
//
//  Created by Maciej Swic on 2011-05-16.
//  Copyright (c) 2011 Maciej Swic, Licensed under the MIT License.
//  See README.md for details
//

#import "iReSignAppDelegate.h"

static NSString *kKeyPrefsBundleIDChange = @"keyBundleIDChange";

static NSString *kKeyBundleIDPlistApp = @"CFBundleIdentifier";
static NSString *kKeyBundleIDPlistiTunesArtwork = @"softwareVersionBundleId";
static NSString *kKeyInfoPlistApplicationProperties = @"ApplicationProperties";
static NSString *kKeyInfoPlistApplicationPath = @"ApplicationPath";
static NSString *kFrameworksDirName = @"Frameworks";
static NSString *kPayloadDirName = @"Payload";
static NSString *kProductsDirName = @"Products";
static NSString *kInfoPlistFilename = @"Info.plist";
static NSString *kiTunesMetadataFileName = @"iTunesMetadata";

@implementation iReSignAppDelegate

@synthesize window, workingPath;

- (void) applicationDidFinishLaunching: (NSNotification *) aNotification
{
	[flurry setAlphaValue: 0.5];
	
	defaults = [NSUserDefaults standardUserDefaults];
	fileManager = [NSFileManager defaultManager];
	notificationCenter = [NSNotificationCenter defaultCenter];
	
	// Look up available signing certificates
	[self getCerts];
	
	if( [defaults valueForKey: @"ENTITLEMENT_PATH"] )
		[entitlementField setStringValue: [defaults valueForKey: @"ENTITLEMENT_PATH"]];
	if( [defaults valueForKey: @"MOBILEPROVISION_PATH"] )
		[provisioningPathField setStringValue: [defaults valueForKey: @"MOBILEPROVISION_PATH"]];
	
	if( ! [fileManager fileExistsAtPath: @"/usr/bin/zip"] )
	{
		[self abort: @"This app cannot run without the zip utility present at /usr/bin/zip"];
		[self disableControls];
	}

	if( ! [fileManager fileExistsAtPath: @"/usr/bin/unzip"] )
	{
		[self abort: @"This app cannot run without the unzip utility present at /usr/bin/unzip"];
		[self disableControls];
	}

	if( ! [fileManager fileExistsAtPath: @"/usr/bin/codesign"] )
	{
		[self abort: @"This app cannot run without the codesign utility present at /usr/bin/codesign"];
		[self disableControls];
	}
}

- (IBAction) resign: (id) sender
{
	[self disableControls];

	//Save cert name
	[defaults setValue: [NSNumber numberWithInteger: [certComboBox indexOfSelectedItem]] forKey: @"CERT_INDEX"];
	[defaults setValue: [entitlementField stringValue] forKey: @"ENTITLEMENT_PATH"];
	[defaults setValue: [provisioningPathField stringValue] forKey: @"MOBILEPROVISION_PATH"];
	[defaults setValue: [bundleIDField stringValue] forKey: kKeyPrefsBundleIDChange];
	[defaults synchronize];
	
	codesigningResult = nil;
	verificationResult = nil;
	
	NSString *certificateIdentity = [certComboBox objectValue];
	sourcePath = [pathField stringValue];
	NSString *sourceExtension = [[sourcePath pathExtension] lowercaseString];

	// validate certificate
	if( ! certificateIdentity )
	{
		[self abort: @"You must choose an signing certificate from dropdown."];

		return;
	}

	[self setUpWorkingDirectory];

	if( [sourceExtension isEqualToString: @"ipa"] )
	{
		[self processIPA];
	}
	else if( [sourceExtension isEqualToString: @"xcarchive"] )
	{
		[self processArchive];
	}
	else
	{
		[self abort: @"You must choose an *.ipa or *.xcarchive file"];
		
		return;
	}
}

- (void) setUpWorkingDirectory
{
	workingPath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"com.appulize.iresign"];

	NSLog( @"Setting up working directory in %@", workingPath );
	[statusLabel setHidden: NO];
	[statusLabel setStringValue: @"Setting up working directory"];
	
	[fileManager removeItemAtPath: workingPath error: nil];
	[fileManager createDirectoryAtPath: workingPath withIntermediateDirectories: TRUE attributes: nil error: nil];
}

- (void) processIPA
{
	NSLog( @"Unzipping %@", sourcePath );
	[statusLabel setStringValue: @"Extracting original app"];
	
	[self executeCommand: @"/usr/bin/unzip"
		withArgs: @[ @"-q", sourcePath, @"-d", workingPath ]
		onTerminate: ^(NSTask *task) {
			if( ! [fileManager fileExistsAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName]] )
			{
				[self abort: @"Unzip failed"];
				
				return;
			}

			NSLog(@"Unzipping done");
			[statusLabel setStringValue: @"Original app extracted"];

			[self processPayload];
		}
	];
}

- (void) processArchive
{
	NSString* payloadPath = [workingPath stringByAppendingPathComponent: kPayloadDirName];
	
	NSLog( @"Setting up %@ path in %@", kPayloadDirName, payloadPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Setting up %@ path", kPayloadDirName]];
	
	[fileManager createDirectoryAtPath: payloadPath withIntermediateDirectories: TRUE attributes: nil error: nil];
	
	NSLog( @"Retrieving %@", kInfoPlistFilename );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Retrieving %@", kInfoPlistFilename]];
	
	NSString* infoPListPath = [sourcePath stringByAppendingPathComponent: kInfoPlistFilename];
	
	NSDictionary* infoPListDict = [NSDictionary dictionaryWithContentsOfFile: infoPListPath];
	
	if( infoPListDict == nil )
	{
		[self abort: [NSString stringWithFormat: @"Retrieve %@ failed", kInfoPlistFilename]];
		
		return;
	}

	NSString* applicationPath = nil;
	NSDictionary* applicationPropertiesDict = [infoPListDict objectForKey: kKeyInfoPlistApplicationProperties];
	
	if( applicationPropertiesDict != nil )
	{
		applicationPath = [applicationPropertiesDict objectForKey: kKeyInfoPlistApplicationPath];
	}
	
	if( applicationPath == nil )
	{
		[self abort: [NSString stringWithFormat: @"Unable to parse %@", kInfoPlistFilename]];
		
		return;
	}
	
	applicationPath = [[sourcePath stringByAppendingPathComponent: kProductsDirName] stringByAppendingPathComponent: applicationPath];
	
	NSLog( @"Copying %@ to %@ path in %@", applicationPath, kPayloadDirName, payloadPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Copying .xcarchive app to %@ path", kPayloadDirName]];

	[self executeCommand: @"/bin/cp"
		withArgs: @[ @"-r", applicationPath, payloadPath ]
		onTerminate: ^(NSTask *task) {
			NSLog(@"Copy done");
			[statusLabel setStringValue: @".xcarchive app copied"];
			
			[self processPayload];
		}
	];
}

- (void) processPayload
{
	NSString *payloadPath = [workingPath stringByAppendingPathComponent: kPayloadDirName];
	appName = [self findFirstFileInDirectory: payloadPath passingTest: ^( NSString *file ) {
		return [[[file pathExtension] lowercaseString] isEqualToString: @"app"];
	}];

	if( appName == nil )
	{
		[self abort: @"No app found."];
		
		return;
	}

	appPath = [payloadPath stringByAppendingPathComponent: appName];
	
	if( changeBundleIDCheckbox.state == NSOnState )
	{
		[self doBundleIDChange: bundleIDField.stringValue];
	}
	
	if( [[provisioningPathField stringValue] isEqualTo: @""] )
	{
		[self doCodeSigning];
	}
	else
	{
		[self doProvisioning];
	}
}

- (void) doBundleIDChange: (NSString *) newBundleID
{
	[self doAppBundleIDChange: newBundleID];
	[self doITunesMetadataBundleIDChange: newBundleID];
}

- (void) doITunesMetadataBundleIDChange: (NSString *) newBundleID
{
	NSString *infoPlistPath = [workingPath stringByAppendingPathComponent: kInfoPlistFilename];
	
	[self changeBundleIDForFile: infoPlistPath bundleIDKey: kKeyBundleIDPlistiTunesArtwork newBundleID: newBundleID plistOutOptions: NSPropertyListXMLFormat_v1_0];
}

- (void) doAppBundleIDChange: (NSString *) newBundleID
{
	NSString *infoPlistPath = infoPlistPath = [appPath stringByAppendingPathComponent: kInfoPlistFilename];
	
	[self changeBundleIDForFile: infoPlistPath bundleIDKey: kKeyBundleIDPlistApp newBundleID: newBundleID plistOutOptions: NSPropertyListBinaryFormat_v1_0];
}

- (void) changeBundleIDForFile: (NSString *) filePath bundleIDKey: (NSString *) bundleIDKey newBundleID: (NSString *) newBundleID plistOutOptions: (NSPropertyListWriteOptions) options
{
	if( ! [fileManager fileExistsAtPath: filePath] )
		return;

	NSMutableDictionary *plist = nil;
	
	plist = [NSMutableDictionary dictionaryWithContentsOfFile: filePath];
	[plist setObject: newBundleID forKey: bundleIDKey];
	
	NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList: plist format: options options: kCFPropertyListImmutable error: nil];
	
	[xmlData writeToFile: filePath atomically: YES];
}

- (void) doProvisioning
{
	NSString *embeddedProvisionPath = [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"];
	
	if( [fileManager fileExistsAtPath: embeddedProvisionPath] )
	{
		NSLog(@"Found embedded.mobileprovision, deleting.");
		[fileManager removeItemAtPath: embeddedProvisionPath error: nil];
	}
	
	[self executeCommand: @"/bin/cp"
		withArgs: @[ [provisioningPathField stringValue], embeddedProvisionPath ]
		onTerminate: ^(NSTask *task) {
			if( ! [fileManager fileExistsAtPath: embeddedProvisionPath] )
			{
				[self abort: @"Provisioning failed"];
				
				return;
			}

			[self checkProvisioning: embeddedProvisionPath];
		}
	];
}

- (void) checkProvisioning: (NSString *) embeddedProvisionPath
{
	[self executeCommand:@"/usr/bin/security"
		withArgs: @[ @"cms", @"-D", @"-i", embeddedProvisionPath ]
		onCompleteReadingOutput: ^(NSString *output) {
			[self checkApplicationIdentifiers: output.propertyList];
		}
	];
}

- (void) checkApplicationIdentifiers: (NSDictionary *) embeddedProvisioning
{
	NSString *fullIdentifier = [embeddedProvisioning valueForKeyPath: @"Entitlements.application-identifier"];
	NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString: @"."];

	NSRange last;
	last.location = 1;
	last.length = [identifierComponents count] - 1;

	NSArray *lastComponents = [identifierComponents subarrayWithRange: last];
	NSString *identifierInProvisioning = [lastComponents componentsJoinedByString: @"."];

	NSLog( @"Mobileprovision identifier: %@", identifierInProvisioning );

	NSDictionary *infoplist = [NSDictionary dictionaryWithContentsOfFile: [appPath stringByAppendingPathComponent: @"Info.plist"]];
	NSString *identifierInInfoPlist = [infoplist objectForKey: kKeyBundleIDPlistApp];

	if(
		[identifierInProvisioning isEqualToString: @"*"] ||
		[identifierInProvisioning isEqualToString: identifierInInfoPlist]
	)
	{
		NSLog(@"Provisioning completed.");
		[statusLabel setStringValue: @"Provisioning completed"];

		[self doEntitlementsFixing];
	}
	else
	{
		[self abort: @"Product identifiers don't match"];
	}
}

- (void) doEntitlementsFixing
{
	if( ! [entitlementField.stringValue isEqualToString: @""] || [provisioningPathField.stringValue isEqualToString: @""] )
	{
		[self doCodeSigning];

		return; // Using a pre-made entitlements file or we're not re-provisioning.
	}
	
	[statusLabel setStringValue: @"Generating entitlements"];

	[self executeCommand:@"/usr/bin/security"
		withArgs:@[ @"cms", @"-D", @"-i", provisioningPathField.stringValue ]
		onCompleteReadingOutput: ^(NSString *output) {
			entitlementsResult = output;

			NSLog(@"Entitlements fixed done");
			[statusLabel setStringValue: @"Entitlements generated"];

			[self doEntitlementsEdit];
		}
	];
}

- (void) doEntitlementsEdit
{
	NSDictionary* entitlements = entitlementsResult.propertyList;
	entitlements = entitlements[@"Entitlements"];
	NSString* filePath = [workingPath stringByAppendingPathComponent: @"entitlements.plist"];
	NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList: entitlements format: NSPropertyListXMLFormat_v1_0 options: kCFPropertyListImmutable error: nil];

	if( ! [xmlData writeToFile: filePath atomically: YES] )
	{
		NSLog(@"Error writing entitlements file.");
		[self abort: @"Failed entitlements generation"];
		
		return;
	}

	entitlementField.stringValue = filePath;
	[self doCodeSigning];
}

- (void) doCodeSigning
{
	frameworksDirPath = nil;
	hasFrameworks = NO;
	frameworks = [[NSMutableArray alloc] init];
	
	frameworksDirPath = [appPath stringByAppendingPathComponent: kFrameworksDirName];
	NSLog( @"Found %@", appPath );
	if( [fileManager fileExistsAtPath: frameworksDirPath] )
	{
		NSLog( @"Found %@", frameworksDirPath );
		hasFrameworks = YES;
		NSArray *frameworksContents = [fileManager contentsOfDirectoryAtPath: frameworksDirPath error: nil];
		for( NSString *frameworkFile in frameworksContents )
		{
			NSString *extension = [[frameworkFile pathExtension] lowercaseString];
			if( [extension isEqualTo: @"framework"] || [extension isEqualTo: @"dylib"] )
			{
				frameworkPath = [frameworksDirPath stringByAppendingPathComponent: frameworkFile];
				NSLog( @"Found %@", frameworkPath );
				[frameworks addObject: frameworkPath];
			}
		}
	}
	[statusLabel setStringValue: [NSString stringWithFormat: @"Codesigning %@", appName]];
	
	if( hasFrameworks )
	{
		[self signFile: [frameworks lastObject]];
		[frameworks removeLastObject];
	}
	else
	{
		[self signFile: appPath];
	}
}

- (void) signFile: (NSString*) filePath
{
	NSLog( @"Codesigning %@", filePath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Codesigning %@", filePath]];
	
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects: @"-fs", [certComboBox objectValue], nil];
	NSDictionary *systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile: @"/System/Library/CoreServices/SystemVersion.plist"];
	NSString * systemVersion = [systemVersionDictionary objectForKey: @"ProductVersion"];
	NSArray * version = [systemVersion componentsSeparatedByString: @"."];
	
	int	v0 = [version[0] intValue];
	int v1 = [version[1] intValue];
	int v2 = [version[2] intValue];

	if(
		v0 > 10 ||
		( v0 == 10 &&
			(
				v1 > 9 ||
				( v1 == 9 && v2 >= 5 )
			)
		)
	)
	{
		/*
		 For OSX 10.9.5 and later, code signing requires a version 2 signature.
		 The resource envelope is obsolete.
		 To ensure it is ignored, remove the resource key from the Info.plist file.
		 */
		
		NSString *infoPath = [NSString stringWithFormat: @"%@/Info.plist", filePath];
		NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile: infoPath];
		[infoDict removeObjectForKey: @"CFBundleResourceSpecification"];
		[infoDict writeToFile: infoPath atomically: YES];
		[arguments addObject: @"--no-strict"]; // http: //stackoverflow.com/a/26204757
	}
	else
	{
		/*
		 Before OSX 10.9.5, code signing requires a version 1 signature.
		 The resource envelope is necessary.
		 To ensure it is added, append the resource flag to the arguments.
		 */
		
		NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource: @"ResourceRules" ofType: @"plist"];
		NSString *resourceRulesArgument = [NSString stringWithFormat: @"--resource-rules=%@", resourceRulesPath];
		[arguments addObject: resourceRulesArgument];
	}
	
	if( ! [[entitlementField stringValue] isEqualToString: @""] )
	{
		[arguments addObject: [NSString stringWithFormat: @"--entitlements=%@", [entitlementField stringValue]]];
	}
	
	[arguments addObject: filePath];
	
	[self executeCommand: @"/usr/bin/codesign"
		withArgs: arguments
		onCompleteReadingOutput: ^(NSString *output) {
			codesigningResult = output;

			[self continueCodesigning];
		}
	];
}

- (void) continueCodesigning
{
	if( frameworks.count > 0 )
	{
		[self signFile: [frameworks lastObject]];
		[frameworks removeLastObject];
	}
	else if( hasFrameworks )
	{
		hasFrameworks = NO;
		[self signFile: appPath];
	}
	else
	{
		NSLog(@"Codesigning done");
		[statusLabel setStringValue: @"Codesigning completed"];
		[self doVerifySignature];
	}
}

- (void) doVerifySignature
{
	NSLog( @"Verifying %@", appPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Verifying %@", appName]];
	
	[self executeCommand: @"/usr/bin/codesign"
		withArgs: @[ @"-v", appPath ]
		onCompleteReadingOutput: ^(NSString *output) {
			verificationResult = output;

			if( [verificationResult length] != 0 )
			{
				NSString *error = [[codesigningResult stringByAppendingString: @"\n\n"] stringByAppendingString: verificationResult];
				[self abort: error];
				
				return;
			}

			NSLog(@"Verification done");
			[statusLabel setStringValue: @"Verification completed"];
			[self doZip];
		}
	];
}

- (void) doZip
{
	NSString *destinationPath = [NSString stringWithFormat: @"%@-resigned.%@",
		[sourcePath stringByDeletingPathExtension],
		[sourcePath pathExtension]
	];
	NSString *resignedFileName = [destinationPath lastPathComponent];

	NSLog( @"Dest: %@", destinationPath );
	
	NSLog( @"Zipping %@", destinationPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Saving %@", resignedFileName]];

	[self executeCommand: @"/usr/bin/zip"
		withArgs: @[ @"-qry", destinationPath, @"." ]
		onTerminate: ^(NSTask *task) {
			NSLog(@"Zipping done");

			[self reportSuccess: resignedFileName];
		}
	];
}

- (void) reportSuccess: (NSString *) resignedFileName
{
	[statusLabel setStringValue: [NSString stringWithFormat: @"Saved %@", resignedFileName]];
	
	[fileManager removeItemAtPath: workingPath error: nil];
	
	[self enableControls];
	
	NSString *result = [[codesigningResult stringByAppendingString: @"\n\n"] stringByAppendingString: verificationResult];
	NSLog( @"Codesigning result: %@", result );
	NSLog(@"Success.");
}

- (IBAction) browse: (id) sender
{
	NSOpenPanel* openDlg = [NSOpenPanel openPanel];
	
	[openDlg setCanChooseFiles: TRUE];
	[openDlg setCanChooseDirectories: FALSE];
	[openDlg setAllowsMultipleSelection: FALSE];
	[openDlg setAllowsOtherFileTypes: FALSE];
	[openDlg setAllowedFileTypes: @[@"ipa", @"IPA", @"xcarchive"]];
	
	if( [openDlg runModal] == NSOKButton )
	{
		NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex: 0] path];
		[pathField setStringValue: fileNameOpened];
	}
}

- (IBAction) provisioningBrowse: (id) sender
{
	NSOpenPanel* openDlg = [NSOpenPanel openPanel];
	
	[openDlg setCanChooseFiles: TRUE];
	[openDlg setCanChooseDirectories: FALSE];
	[openDlg setAllowsMultipleSelection: FALSE];
	[openDlg setAllowsOtherFileTypes: FALSE];
	[openDlg setAllowedFileTypes: @[@"mobileprovision", @"MOBILEPROVISION"]];
	
	if( [openDlg runModal] == NSOKButton )
	{
		NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex: 0] path];
		[provisioningPathField setStringValue: fileNameOpened];
	}
}

- (IBAction) entitlementBrowse: (id) sender
{
	NSOpenPanel* openDlg = [NSOpenPanel openPanel];
	
	[openDlg setCanChooseFiles: TRUE];
	[openDlg setCanChooseDirectories: FALSE];
	[openDlg setAllowsMultipleSelection: FALSE];
	[openDlg setAllowsOtherFileTypes: FALSE];
	[openDlg setAllowedFileTypes: @[@"plist", @"PLIST"]];
	
	if( [openDlg runModal] == NSOKButton )
	{
		NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex: 0] path];
		[entitlementField setStringValue: fileNameOpened];
	}
}

- (IBAction) changeBundleIDPressed: (id) sender
{
	if( sender != changeBundleIDCheckbox )
		return;
	
	bundleIDField.enabled = changeBundleIDCheckbox.state == NSOnState;
}

- (void) disableControls
{
	[pathField setEnabled: FALSE];
	[entitlementField setEnabled: FALSE];
	[browseButton setEnabled: FALSE];
	[resignButton setEnabled: FALSE];
	[provisioningBrowseButton setEnabled: NO];
	[provisioningPathField setEnabled: NO];
	[changeBundleIDCheckbox setEnabled: NO];
	[bundleIDField setEnabled: NO];
	[certComboBox setEnabled: NO];
	
	[flurry startAnimation: self];
	[flurry setAlphaValue: 1.0];
}

- (void) enableControls
{
	[pathField setEnabled: TRUE];
	[entitlementField setEnabled: TRUE];
	[browseButton setEnabled: TRUE];
	[resignButton setEnabled: TRUE];
	[provisioningBrowseButton setEnabled: YES];
	[provisioningPathField setEnabled: YES];
	[changeBundleIDCheckbox setEnabled: YES];
	[bundleIDField setEnabled: changeBundleIDCheckbox.state == NSOnState];
	[certComboBox setEnabled: YES];
	
	[flurry stopAnimation: self];
	[flurry setAlphaValue: 0.5];
}

- (NSInteger) numberOfItemsInComboBox: (NSComboBox *) aComboBox
{
	NSInteger count = 0;

	if( [aComboBox isEqual: certComboBox] )
	{
		count = [certComboBoxItems count];
	}

	return count;
}

- (id) comboBox: (NSComboBox *) aComboBox objectValueForItemAtIndex: (NSInteger) index
{
	id item = nil;

	if( [aComboBox isEqual: certComboBox] )
	{
		item = [certComboBoxItems objectAtIndex: index];
	}

	return item;
}

- (void) getCerts
{
	getCertsResult = nil;
	
	NSLog(@"Getting Certificate IDs");
	[statusLabel setStringValue: @"Getting Signing Certificate IDs"];
	
	[self executeCommand: @"/usr/bin/security"
		withArgs: @[ @"find-identity", @"-v", @"-p", @"codesigning" ]
		onCompleteReadingOutput: ^(NSString *output) {
			[self checkCerts: output];
		}
	];
}

- (void) parseCerts: (NSString *) certData
{
	// Verify the security result
	if( certData == nil || certData.length < 1 )
	{
		// Nothing in the result, return
		return;
	}

	NSArray *rawResult = [certData componentsSeparatedByString: @"\""];
	NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity: 20];
	for( int i = 0; i <= [rawResult count] - 2; i += 2 )
	{
		NSLog( @"i: %d", i + 1 );
		if( rawResult.count - 1 >= i + 1 )
		{
			// Valid object
			[tempGetCertsResult addObject: [rawResult objectAtIndex: i + 1]];
		}
	}
	
	certComboBoxItems = [NSMutableArray arrayWithArray: tempGetCertsResult];
	
	[certComboBox reloadData];
}

- (void) checkCerts: (NSString *) output
{
	[self parseCerts: output];
	
	if( [certComboBoxItems count] == 0 )
	{
		[self abort: @"Getting Certificate ID's failed"];
		
		return;
	}

	NSLog(@"Get Certs done");
	[statusLabel setStringValue: @"Signing Certificate IDs extracted"];
	
	long certIndex = -1;
	NSArray *args = [[NSProcessInfo processInfo] arguments];
	if( args.count == 2 )
	{
		NSURL *plistURL = [NSURL fileURLWithPath: [args objectAtIndex: 1]];
		
		// cwd to plist directory so that paths are relative to the plist
		[fileManager changeCurrentDirectoryPath: [[plistURL path] stringByDeletingLastPathComponent]];
		
		NSDictionary *params = [NSDictionary dictionaryWithContentsOfFile: [plistURL path]];
		
		NSString *mobileProvisionPath = [params objectForKey: @"mobile-provision-path"];
		NSString *entitlementsPath = [params objectForKey: @"entitlements-path"];
		NSString *bundleID = [params objectForKey: @"bundle-id"];
		NSString *certificateIdentity = [params objectForKey: @"certificate-identity"];
		NSString *ipaPath = [params objectForKey: @"ipa-path"];
		
		if( mobileProvisionPath != nil )
			provisioningPathField.stringValue = [[NSURL fileURLWithPath: mobileProvisionPath] path];
		
		if( entitlementsPath != nil )
			entitlementField.stringValue = [[NSURL fileURLWithPath: entitlementsPath] path];
		
		if( bundleID != nil )
		{
			bundleIDField.stringValue = bundleID;
			changeBundleIDCheckbox.state = NSOnState;
		}
		else
		{
			bundleIDField.stringValue = @"";
			changeBundleIDCheckbox.state = NSOffState;
		}
		
		if( certificateIdentity != nil )
		{
			certIndex = (long) [certComboBoxItems indexOfObject: certificateIdentity];
		}

		if( ipaPath != nil )
		{
			pathField.stringValue = [[NSURL fileURLWithPath: ipaPath] path];
			[self resign: self];
		}
	}
	else
	{
		if( [defaults valueForKey: @"CERT_INDEX"] )
			certIndex = (long) [defaults valueForKey: @"CERT_INDEX"];
	}

	if( certIndex >= 0 )
	{
		NSString *selectedItem = [self comboBox: certComboBox objectValueForItemAtIndex: certIndex];
		[certComboBox setObjectValue: selectedItem];
		[certComboBox selectItemAtIndex: certIndex];
		
		[self enableControls];
	}
}

// If the application dock icon is clicked, reopen the window
- (BOOL) applicationShouldHandleReopen: (NSApplication *) sender hasVisibleWindows: (BOOL) flag
{
	// Make sure the window is visible
	if( ! [self.window isVisible] )
	{
		// Window isn't shown, show it
		[self.window makeKeyAndOrderFront: self];
	}
	
	return YES;
}

- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onTerminate: (void (^)(NSTask *)) completion
{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath: executablePath];
	[task setArguments: args];

	[notificationCenter addObserverForName: NSTaskDidTerminateNotification
		object: task
		queue: nil
		usingBlock: ^( NSNotification *notification ) {
			completion( [notification object] );
		}
	];
	
	[task launch];
}

- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onCompleteReadingOutput: (void (^)(NSString *)) completion
{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath: executablePath];
	[task setArguments: args];

	NSPipe *pipe = [NSPipe pipe];
	[task setStandardOutput: pipe];
	[task setStandardError: pipe];
	
	NSFileHandle *handle = [pipe fileHandleForReading];

	[notificationCenter addObserverForName: NSFileHandleReadToEndOfFileCompletionNotification
		object: handle
		queue: nil
		usingBlock: ^( NSNotification *notification ) {
			NSString *output = [[NSString alloc]
				initWithData: [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem]
				encoding: NSASCIIStringEncoding
			];

			completion( output );
		}
	];

    [handle readToEndOfFileInBackgroundAndNotify];

	[task launch];
}

- (NSString *) findFirstFileInDirectory: (NSString *) directory passingTest: ( BOOL (^)( NSString *fileName ) ) test
{
	NSArray *directoryContents = [fileManager contentsOfDirectoryAtPath: directory error: nil];
	NSUInteger index = [directoryContents indexOfObjectPassingTest: ^( NSString *file, NSUInteger index, BOOL *stop ) {
		return test( file );
	}];

	if( index == NSNotFound )
		return nil;

	return [directoryContents objectAtIndex: index];
}

#pragma mark - Alert Methods

// Show a critical alert
- (void) showAlertOfKind: (NSAlertStyle) style withTitle: (NSString *) title andMessage: (NSString *) message
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert addButtonWithTitle: @"OK"];
	[alert setMessageText: title];
	[alert setInformativeText: message];
	[alert setAlertStyle: style];
	[alert runModal];
}

- (void) abort: (NSString *) message
{
	[self showAlertOfKind: NSCriticalAlertStyle withTitle: @"Error" andMessage: message];
	[self enableControls];

	[statusLabel setStringValue: @"Ready"];
}

@end
