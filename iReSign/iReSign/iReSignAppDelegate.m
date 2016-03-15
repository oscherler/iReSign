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
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"This app cannot run without the zip utility present at /usr/bin/zip"];
		exit( 0 );
	}

	if( ! [fileManager fileExistsAtPath: @"/usr/bin/unzip"] )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"This app cannot run without the unzip utility present at /usr/bin/unzip"];
		exit( 0 );
	}

	if( ! [fileManager fileExistsAtPath: @"/usr/bin/codesign"] )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"This app cannot run without the codesign utility present at /usr/bin/codesign"];
		exit( 0 );
	}
}

- (IBAction) resign: (id) sender
{
	//Save cert name
	[defaults setValue: [NSNumber numberWithInteger: [certComboBox indexOfSelectedItem]] forKey: @"CERT_INDEX"];
	[defaults setValue: [entitlementField stringValue] forKey: @"ENTITLEMENT_PATH"];
	[defaults setValue: [provisioningPathField stringValue] forKey: @"MOBILEPROVISION_PATH"];
	[defaults setValue: [bundleIDField stringValue] forKey: kKeyPrefsBundleIDChange];
	[defaults synchronize];
	
	codesigningResult = nil;
	verificationResult = nil;
	
	sourcePath = [pathField stringValue];
	workingPath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"com.appulize.iresign"];
	
	if( ! [certComboBox objectValue] )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"You must choose an signing certificate from dropdown."];
		[self enableControls];
		[statusLabel setStringValue: @"Please try again"];

		return;
	}

	NSString *sourceExtension = [[sourcePath pathExtension] lowercaseString];

	if( ! [sourceExtension isEqualToString: @"ipa"] && ! [sourceExtension isEqualToString: @"xcarchive"] )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"You must choose an *.ipa or *.xcarchive file"];
		[self enableControls];
		[statusLabel setStringValue: @"Please try again"];
		
		return;
	}

	[self disableControls];
	
	NSLog( @"Setting up working directory in %@", workingPath );
	[statusLabel setHidden: NO];
	[statusLabel setStringValue: @"Setting up working directory"];
	
	[fileManager removeItemAtPath: workingPath error: nil];
	
	[fileManager createDirectoryAtPath: workingPath withIntermediateDirectories: TRUE attributes: nil error: nil];
	
	if( [[[sourcePath pathExtension] lowercaseString] isEqualToString: @"ipa"] )
	{
		NSLog( @"Unzipping %@", sourcePath );
		[statusLabel setStringValue: @"Extracting original app"];
		
		[self executeCommand: @"/usr/bin/unzip"
			withArgs: [NSArray arrayWithObjects: @"-q", sourcePath, @"-d", workingPath, nil]
			onTerminate: @selector( checkUnzip: )
		];
	}
	else
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
			[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: [NSString stringWithFormat: @"Retrieve %@ failed", kInfoPlistFilename]];
			[self enableControls];
			[statusLabel setStringValue: @"Ready"];
			
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
			[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: [NSString stringWithFormat: @"Unable to parse %@", kInfoPlistFilename]];
			[self enableControls];
			[statusLabel setStringValue: @"Ready"];
			
			return;
		}
		
		applicationPath = [[sourcePath stringByAppendingPathComponent: kProductsDirName] stringByAppendingPathComponent: applicationPath];
		
		NSLog( @"Copying %@ to %@ path in %@", applicationPath, kPayloadDirName, payloadPath );
		[statusLabel setStringValue: [NSString stringWithFormat: @"Copying .xcarchive app to %@ path", kPayloadDirName]];

		[self executeCommand: @"/bin/cp"
			withArgs: [NSArray arrayWithObjects: @"-r", applicationPath, payloadPath, nil]
			onTerminate: @selector( checkCopy: )
		];
	}
}

- (void) checkUnzip: (NSNotification *) notification
{
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];
	
	if( ! [fileManager fileExistsAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName]] )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"Unzip failed"];
		[self enableControls];
		[statusLabel setStringValue: @"Ready"];
		
		return;
	}

	NSLog(@"Unzipping done");
	[statusLabel setStringValue: @"Original app extracted"];

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

- (void) checkCopy: (NSNotification *) notification
{
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];
	
	NSLog(@"Copy done");
	[statusLabel setStringValue: @".xcarchive app copied"];
	
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

- (BOOL) doBundleIDChange: (NSString *) newBundleID
{
	BOOL success = YES;
	
	success &= [self doAppBundleIDChange: newBundleID];
	success &= [self doITunesMetadataBundleIDChange: newBundleID];
	
	return success;
}

- (BOOL) doITunesMetadataBundleIDChange: (NSString *) newBundleID
{
	NSArray *dirContents = [fileManager contentsOfDirectoryAtPath: workingPath error: nil];
	NSString *infoPlistPath = nil;
	
	for( NSString *file in dirContents )
	{
		if( [[[file pathExtension] lowercaseString] isEqualToString: @"plist"] )
		{
			infoPlistPath = [workingPath stringByAppendingPathComponent: file];
			break;
		}
	}
	
	return [self changeBundleIDForFile: infoPlistPath bundleIDKey: kKeyBundleIDPlistiTunesArtwork newBundleID: newBundleID plistOutOptions: NSPropertyListXMLFormat_v1_0];
	
}

- (BOOL) doAppBundleIDChange: (NSString *) newBundleID
{
	NSArray *dirContents = [fileManager contentsOfDirectoryAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName] error: nil];
	NSString *infoPlistPath = nil;
	
	for( NSString *file in dirContents )
	{
		if( [[[file pathExtension] lowercaseString] isEqualToString: @"app"] )
		{
			infoPlistPath = [[[workingPath stringByAppendingPathComponent: kPayloadDirName]
				stringByAppendingPathComponent: file]
				stringByAppendingPathComponent: kInfoPlistFilename
			];
			break;
		}
	}
	
	return [self changeBundleIDForFile: infoPlistPath bundleIDKey: kKeyBundleIDPlistApp newBundleID: newBundleID plistOutOptions: NSPropertyListBinaryFormat_v1_0];
}

- (BOOL) changeBundleIDForFile: (NSString *) filePath bundleIDKey: (NSString *) bundleIDKey newBundleID: (NSString *) newBundleID plistOutOptions: (NSPropertyListWriteOptions) options
{
	if( ! [fileManager fileExistsAtPath: filePath] )
		return NO;

	NSMutableDictionary *plist = nil;
	
	plist = [[NSMutableDictionary alloc] initWithContentsOfFile: filePath];
	[plist setObject: newBundleID forKey: bundleIDKey];
	
	NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList: plist format: options options: kCFPropertyListImmutable error: nil];
	
	return [xmlData writeToFile: filePath atomically: YES];
}

- (void) doProvisioning
{
	NSArray *dirContents = [fileManager contentsOfDirectoryAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName] error: nil];
	
	for( NSString *file in dirContents )
	{
		if( [[[file pathExtension] lowercaseString] isEqualToString: @"app"] )
		{
			appPath = [[workingPath stringByAppendingPathComponent: kPayloadDirName] stringByAppendingPathComponent: file];
			if( [fileManager fileExistsAtPath: [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"]] )
			{
				NSLog(@"Found embedded.mobileprovision, deleting.");
				[fileManager removeItemAtPath: [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"] error: nil];
			}
			break;
		}
	}
	
	NSString *targetPath = [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"];

	[self executeCommand: @"/bin/cp"
		withArgs: [NSArray arrayWithObjects: [provisioningPathField stringValue], targetPath, nil]
		onTerminate: @selector( checkProvisioning: )
	];
}

- (void) checkProvisioning: (NSNotification *) notification
{
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];
	
	NSArray *dirContents = [fileManager contentsOfDirectoryAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName] error: nil];
	
	for( NSString *file in dirContents )
	{
		if( [[[file pathExtension] lowercaseString] isEqualToString: @"app"] )
		{
			appPath = [[workingPath stringByAppendingPathComponent: kPayloadDirName] stringByAppendingPathComponent: file];
			if( ! [fileManager fileExistsAtPath: [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"]] )
			{
				[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"Provisioning failed"];
				[self enableControls];
				[statusLabel setStringValue: @"Ready"];
				
				continue;
			}
			
			BOOL identifierOK = FALSE;
			NSString *identifierInProvisioning = @"";
			
			NSString *embeddedProvisioning = [NSString stringWithContentsOfFile: [appPath stringByAppendingPathComponent: @"embedded.mobileprovision"] encoding: NSASCIIStringEncoding error: nil];
			NSArray* embeddedProvisioningLines = [embeddedProvisioning componentsSeparatedByCharactersInSet: 
				[NSCharacterSet newlineCharacterSet]
			];
			
			for( int i = 0; i < [embeddedProvisioningLines count]; i++ )
			{
				if( [[embeddedProvisioningLines objectAtIndex: i] rangeOfString: @"application-identifier"].location != NSNotFound )
				{
					NSInteger fromPosition = [[embeddedProvisioningLines objectAtIndex: i + 1] rangeOfString: @"<string>"].location + 8;
					
					NSInteger toPosition = [[embeddedProvisioningLines objectAtIndex: i + 1] rangeOfString: @"</string>"].location;
					
					NSRange range;
					range.location = fromPosition;
					range.length = toPosition - fromPosition;
					
					NSString *fullIdentifier = [[embeddedProvisioningLines objectAtIndex: i + 1] substringWithRange: range];
					
					NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString: @"."];
					
					if( [[identifierComponents lastObject] isEqualTo: @"*"] )
					{
						identifierOK = TRUE;
					}
					
					for( int i = 1; i < [identifierComponents count]; i++ )
					{
						identifierInProvisioning = [identifierInProvisioning stringByAppendingString: [identifierComponents objectAtIndex: i]];
						if( i < [identifierComponents count] - 1 )
						{
							identifierInProvisioning = [identifierInProvisioning stringByAppendingString: @"."];
						}
					}
					break;
				}
			}
			
			NSLog( @"Mobileprovision identifier: %@", identifierInProvisioning );
			
			NSDictionary *infoplist = [NSDictionary dictionaryWithContentsOfFile: [appPath stringByAppendingPathComponent: @"Info.plist"]];
			if( [identifierInProvisioning isEqualTo: [infoplist objectForKey: kKeyBundleIDPlistApp]] )
			{
				NSLog(@"Identifiers match");
				identifierOK = TRUE;
			}
			
			if( identifierOK )
			{
				NSLog(@"Provisioning completed.");
				[statusLabel setStringValue: @"Provisioning completed"];
				[self doEntitlementsFixing];
			}
			else
			{
				[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"Product identifiers don't match"];
				[self enableControls];
				[statusLabel setStringValue: @"Ready"];
			}

			break;
		}
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

	if( ! appPath )
		return;

	NSTask *generateEntitlementsTask = [[NSTask alloc] init];
	[generateEntitlementsTask setLaunchPath: @"/usr/bin/security"];
	[generateEntitlementsTask setArguments: @[@"cms", @"-D", @"-i", provisioningPathField.stringValue]];
	[generateEntitlementsTask setCurrentDirectoryPath: workingPath];

	NSPipe *pipe = [NSPipe pipe];
	[generateEntitlementsTask setStandardOutput: pipe];
	[generateEntitlementsTask setStandardError: pipe];

	[notificationCenter addObserver: self selector: @selector( checkEntitlementsFix: ) name:NSFileHandleReadToEndOfFileCompletionNotification object: [pipe fileHandleForReading]];
    [[pipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];

	[generateEntitlementsTask launch];
}

- (void) watchEntitlements: (NSNotification *) notification
{
	entitlementsResult = [[NSString alloc] initWithData: [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
}

- (void) checkEntitlementsFix: (NSNotification *) notification
{
	[self watchEntitlements: notification];
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];

	NSLog(@"Entitlements fixed done");
	[statusLabel setStringValue: @"Entitlements generated"];
	[self doEntitlementsEdit];
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
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"Failed entitlements generation"];
		[self enableControls];
		[statusLabel setStringValue: @"Ready"];
		
		return;
	}

	entitlementField.stringValue = filePath;
	[self doCodeSigning];
}

- (void) doCodeSigning
{
	appPath = nil;
	frameworksDirPath = nil;
	hasFrameworks = NO;
	frameworks = [[NSMutableArray alloc] init];
	
	NSArray *dirContents = [fileManager contentsOfDirectoryAtPath: [workingPath stringByAppendingPathComponent: kPayloadDirName] error: nil];
	
	for( NSString *file in dirContents )
	{
		if( [[[file pathExtension] lowercaseString] isEqualToString: @"app"] )
		{
			appPath = [[workingPath stringByAppendingPathComponent: kPayloadDirName] stringByAppendingPathComponent: file];
			frameworksDirPath = [appPath stringByAppendingPathComponent: kFrameworksDirName];
			NSLog( @"Found %@", appPath );
			appName = file;
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
			[statusLabel setStringValue: [NSString stringWithFormat: @"Codesigning %@", file]];
			break;
		}
	}
	
	if( appPath )
	{
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
}

- (void) signFile: (NSString*) filePath
{
	NSLog( @"Codesigning %@", filePath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Codesigning %@", filePath]];
	
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects: @"-fs", [certComboBox objectValue], nil];
	NSDictionary *systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile: @"/System/Library/CoreServices/SystemVersion.plist"];
	NSString * systemVersion = [systemVersionDictionary objectForKey: @"ProductVersion"];
	NSArray * version = [systemVersion componentsSeparatedByString: @"."];
	if( [version[0] intValue] < 10 || ( [version[0] intValue] == 10 && ( [version[1] intValue] < 9 || ( [version[1] intValue] == 9 && [version[2] intValue] < 5 ) ) ) )
	{
		/*
		 Before OSX 10.9, code signing requires a version 1 signature.
		 The resource envelope is necessary.
		 To ensure it is added, append the resource flag to the arguments.
		 */
		
		NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource: @"ResourceRules" ofType: @"plist"];
		NSString *resourceRulesArgument = [NSString stringWithFormat: @"--resource-rules=%@", resourceRulesPath];
		[arguments addObject: resourceRulesArgument];
	}
	else
	{
		/*
		 For OSX 10.9 and later, code signing requires a version 2 signature.
		 The resource envelope is obsolete.
		 To ensure it is ignored, remove the resource key from the Info.plist file.
		 */
		
		NSString *infoPath = [NSString stringWithFormat: @"%@/Info.plist", filePath];
		NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile: infoPath];
		[infoDict removeObjectForKey: @"CFBundleResourceSpecification"];
		[infoDict writeToFile: infoPath atomically: YES];
		[arguments addObject: @"--no-strict"]; // http: //stackoverflow.com/a/26204757
	}
	
	if( ! [[entitlementField stringValue] isEqualToString: @""] )
	{
		[arguments addObject: [NSString stringWithFormat: @"--entitlements=%@", [entitlementField stringValue]]];
	}
	
	[arguments addObjectsFromArray: [NSArray arrayWithObjects: filePath, nil]];
	
	NSTask *codesignTask = [[NSTask alloc] init];
	[codesignTask setLaunchPath: @"/usr/bin/codesign"];
	[codesignTask setArguments: arguments];
	
	NSPipe *pipe = [NSPipe pipe];
	[codesignTask setStandardOutput: pipe];
	[codesignTask setStandardError: pipe];

	[notificationCenter addObserver: self selector: @selector( checkCodesigning: ) name:NSFileHandleReadToEndOfFileCompletionNotification object: [pipe fileHandleForReading]];
    [[pipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
	
	[codesignTask launch];
}

- (void) watchCodesigning: (NSNotification *) notification
{
	codesigningResult = [[NSString alloc] initWithData: [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
}

- (void) checkCodesigning: (NSNotification *) notification
{
	[self watchCodesigning: notification];
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];

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
	if( ! appPath )
		return;

	NSTask *verifyTask = [[NSTask alloc] init];
	[verifyTask setLaunchPath: @"/usr/bin/codesign"];
	[verifyTask setArguments: [NSArray arrayWithObjects: @"-v", appPath, nil]];
	
	NSLog( @"Verifying %@", appPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Verifying %@", appName]];
	
	NSPipe *pipe = [NSPipe pipe];
	[verifyTask setStandardOutput: pipe];
	[verifyTask setStandardError: pipe];

	[notificationCenter addObserver: self selector: @selector( checkVerificationProcess: ) name:NSFileHandleReadToEndOfFileCompletionNotification object: [pipe fileHandleForReading]];
    [[pipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
	
	[verifyTask launch];
}

- (void) watchVerificationProcess: (NSNotification *) notification
{
	verificationResult = [[NSString alloc] initWithData: [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
}

- (void) checkVerificationProcess: (NSNotification *) notification
{
	[self watchVerificationProcess: notification];
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];

	if( [verificationResult length] == 0 )
	{
		NSLog(@"Verification done");
		[statusLabel setStringValue: @"Verification completed"];
		[self doZip];
	}
	else
	{
		NSString *error = [[codesigningResult stringByAppendingString: @"\n\n"] stringByAppendingString: verificationResult];
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Signing failed" AndMessage: error];
		[self enableControls];
		[statusLabel setStringValue: @"Please try again"];
	}
}

- (void) doZip
{
	if( ! appPath )
		return;

	NSArray *destinationPathComponents = [sourcePath pathComponents];
	NSString *destinationPath = @"";
	
	for( int i = 0; i < ([destinationPathComponents count] - 1); i++ )
	{
		destinationPath = [destinationPath stringByAppendingPathComponent: [destinationPathComponents objectAtIndex: i]];
	}
	
	fileName = [sourcePath lastPathComponent];
	fileName = [fileName substringToIndex: ([fileName length] - ([[sourcePath pathExtension] length] + 1))];
	fileName = [fileName stringByAppendingString: @"-resigned"];
	fileName = [fileName stringByAppendingPathExtension: @"ipa"];
	
	destinationPath = [destinationPath stringByAppendingPathComponent: fileName];
	
	NSLog( @"Dest: %@", destinationPath );
	
	NSLog( @"Zipping %@", destinationPath );
	[statusLabel setStringValue: [NSString stringWithFormat: @"Saving %@", fileName]];

	[self executeCommand: @"/usr/bin/zip"
		withArgs: [NSArray arrayWithObjects: @"-qry", destinationPath, @".", nil]
		onTerminate: @selector( checkZip: )
	];
}

- (void) checkZip: (NSNotification *) notification
{
	[notificationCenter removeObserver: self name: NSTaskDidTerminateNotification object: [notification object]];

	NSLog(@"Zipping done");
	[statusLabel setStringValue: [NSString stringWithFormat: @"Saved %@", fileName]];
	
	[fileManager removeItemAtPath: workingPath error: nil];
	
	[self enableControls];
	
	NSString *result = [[codesigningResult stringByAppendingString: @"\n\n"] stringByAppendingString: verificationResult];
	NSLog( @"Codesigning result: %@", result );
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
	
	NSTask *certTask = [[NSTask alloc] init];
	[certTask setLaunchPath: @"/usr/bin/security"];
	[certTask setArguments: [NSArray arrayWithObjects: @"find-identity", @"-v", @"-p", @"codesigning", nil]];
	
	NSPipe *pipe = [NSPipe pipe];
	[certTask setStandardOutput: pipe];
	[certTask setStandardError: pipe];

	[notificationCenter addObserver: self selector: @selector( checkCerts: ) name:NSFileHandleReadToEndOfFileCompletionNotification object: [pipe fileHandleForReading]];
    [[pipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
	
	[certTask launch];
}

- (void) watchGetCerts: (NSNotification *) notification
{
	NSString *securityResult = [[NSString alloc] initWithData: [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem] encoding: NSASCIIStringEncoding];
	// Verify the security result
	if( securityResult == nil || securityResult.length < 1 )
	{
		// Nothing in the result, return
		return;
	}

	NSArray *rawResult = [securityResult componentsSeparatedByString: @"\""];
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

- (void) checkCerts: (NSNotification *) notification
{
	[self watchGetCerts: notification];
	[notificationCenter removeObserver: self name: NSFileHandleReadToEndOfFileCompletionNotification object: [notification object]];
	
	if( [certComboBoxItems count] == 0 )
	{
		[self showAlertOfKind: NSCriticalAlertStyle WithTitle: @"Error" AndMessage: @"Getting Certificate ID's failed"];
		[self enableControls];
		[statusLabel setStringValue: @"Ready"];
		
		return;
	}

	NSLog(@"Get Certs done");
	[statusLabel setStringValue: @"Signing Certificate IDs extracted"];
	
	if( [defaults valueForKey: @"CERT_INDEX"] )
	{
		NSInteger selectedIndex = [[defaults valueForKey: @"CERT_INDEX"] integerValue];
		if( selectedIndex != -1 )
		{
			NSString *selectedItem = [self comboBox: certComboBox objectValueForItemAtIndex: selectedIndex];
			[certComboBox setObjectValue: selectedItem];
			[certComboBox selectItemAtIndex: selectedIndex];
		}
		
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

- (void) executeCommand: (NSString *) executablePath withArgs: (NSArray *) args onTerminate: (SEL) selector
{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath: executablePath];
	[task setArguments: args];
		
	[notificationCenter addObserver: self selector: selector name: NSTaskDidTerminateNotification object: task];
		
	[task launch];
}

#pragma mark - Alert Methods

/* NSRunAlerts are being deprecated in 10.9 */

// Show a critical alert
- (void) showAlertOfKind: (NSAlertStyle) style WithTitle: (NSString *) title AndMessage: (NSString *) message
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert addButtonWithTitle: @"OK"];
	[alert setMessageText: title];
	[alert setInformativeText: message];
	[alert setAlertStyle: style];
	[alert runModal];
}

@end
