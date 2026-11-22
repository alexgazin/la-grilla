#!/usr/bin/env python3
"""Generate the committed Xcode project from repository sources, without a Mac dependency."""
import hashlib,json,pathlib,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]
objects={}
def ident(key):return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def obj(key,isa,**values):
 i=ident(key);objects[i]={'isa':isa,**values};return i
def config(name,values):return obj('config:'+name,'XCBuildConfiguration',buildSettings=values,name=name.rsplit(':',1)[-1])
def configurations(key,base):
 refs=[]
 for name in ['Debug','Release']:
  values=dict(base)
  values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','GCC_OPTIMIZATION_LEVEL':'0' if name=='Debug' else 's'})
  if name=='Debug':values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG';values['ENABLE_TESTABILITY']='YES'
  refs.append(config(key+':'+name,values))
 return obj('configlist:'+key,'XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
def ref(path,type):return obj('file:'+path,'PBXFileReference',lastKnownFileType=type,path=path,sourceTree='SOURCE_ROOT')
def build(key,reference,product=False):return obj('build:'+key,'PBXBuildFile',**({'productRef':reference} if product else {'fileRef':reference}))
base={'SWIFT_VERSION':'6.0','CLANG_CXX_LANGUAGE_STANDARD':'c++17','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO'}
sources=[];groups=[]
for folder in ['App','Features','AudioRuntime','UITests','Demos']:
 files=[]
 for p in sorted((ROOT/folder).glob('*.swift')):
  if folder=='Demos' and p.name!='NativeDemoTests.swift':continue
  path=str(p.relative_to(ROOT));f=ref(path,'sourcecode.swift');files.append(f)
  if folder not in ['UITests','Demos']:sources.append(build(path,f))
 groups.append(obj('group:'+folder,'PBXGroup',children=files,name=folder,sourceTree='<group>'))
assets=ref('Resources/Assets.xcassets','folder.assetcatalog')
localized=[ref('Resources/'+lang+'.lproj/Localizable.strings','text.plist.strings') for lang in ['en','ru']]
# Variant group children use names corresponding to localization regions.
for f,lang in zip(localized,['en','ru']):objects[f]['name']=lang
strings=obj('strings','PBXVariantGroup',children=localized,name='Localizable.strings',sourceTree='<group>')
info_localized=[ref('Resources/'+lang+'.lproj/InfoPlist.strings','text.plist.strings') for lang in ['en','ru']]
for f,lang in zip(info_localized,['en','ru']):objects[f]['name']=lang
info_strings=obj('info_strings','PBXVariantGroup',children=info_localized,name='InfoPlist.strings',sourceTree='<group>')
plural_localized=[ref('Resources/'+lang+'.lproj/Localizable.stringsdict','text.plist.xml') for lang in ['en','ru']]
for f,lang in zip(plural_localized,['en','ru']):objects[f]['name']=lang
plurals=obj('plurals','PBXVariantGroup',children=plural_localized,name='Localizable.stringsdict',sourceTree='<group>')
resource_refs=[assets,strings,info_strings,plurals]
factory=ROOT/'Resources/FactoryInstruments'
if factory.is_dir():resource_refs.append(ref(str(factory.relative_to(ROOT)),'folder'))
launch=ROOT/'Resources/LaunchScreen.storyboard'
if launch.exists():resource_refs.append(ref(str(launch.relative_to(ROOT)),'file.storyboard'))
privacy=ROOT/'Resources/PrivacyInfo.xcprivacy'
if privacy.exists():resource_refs.append(ref(str(privacy.relative_to(ROOT)),'text.xml'))
groups.append(obj('group:Resources','PBXGroup',children=resource_refs,name='Resources',sourceTree='<group>'))
package=obj('package:MusicDomain','XCLocalSwiftPackageReference',relativePath='Packages/MusicDomain')
products=[obj('product:'+name,'XCSwiftPackageProductDependency',productName=name) for name in ['MusicDomain','AudioDSP']]
app_product=obj('app-product','PBXFileReference',explicitFileType='wrapper.application',path='LaGrilla.app',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
test_product=obj('test-product','PBXFileReference',explicitFileType='wrapper.cfbundle',path='LaGrillaUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
demo_product=obj('demo-product','PBXFileReference',explicitFileType='wrapper.cfbundle',path='LaGrillaDemoTests.xctest',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
productgroup=obj('products','PBXGroup',children=[app_product,test_product,demo_product],name='Products',sourceTree='<group>')
rootgroup=obj('rootgroup','PBXGroup',children=groups+[productgroup],sourceTree='<group>')
app_id=ident('target:LaGrilla');test_id=ident('target:LaGrillaUITests');demo_id=ident('target:LaGrillaDemoTests')
def phase(key,isa,files):return obj('phase:'+key,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
appsettings=dict(base,PRODUCT_BUNDLE_IDENTIFIER='com.alexgazin.LaGrilla',PRODUCT_NAME='$(TARGET_NAME)',GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='App/Info.plist',MARKETING_VERSION='1.0.0',CURRENT_PROJECT_VERSION='47',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',INFOPLIST_KEY_CFBundleDisplayName='La Grilla',INFOPLIST_KEY_LSApplicationCategoryType='public.app-category.music',INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',INFOPLIST_KEY_UISupportedInterfaceOrientations='UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight')
if launch.exists():appsettings['INFOPLIST_KEY_UILaunchStoryboardName']='LaunchScreen'
app=obj('target:LaGrilla','PBXNativeTarget',buildConfigurationList=configurations('app',appsettings),buildPhases=[phase('app-source','PBXSourcesBuildPhase',sources),phase('app-frameworks','PBXFrameworksBuildPhase',[build('dependency:'+p,p,True) for p in products]),phase('app-resources','PBXResourcesBuildPhase',[build('resource:'+r,r) for r in resource_refs])],buildRules=[],dependencies=[],name='LaGrilla',packageProductDependencies=products,productName='LaGrilla',productReference=app_product,productType='com.apple.product-type.application')
proxy=obj('proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=app_id,remoteInfo='LaGrilla')
dep=obj('testdependency','PBXTargetDependency',target=app_id,targetProxy=proxy)
testsettings=dict(base,PRODUCT_BUNDLE_IDENTIFIER='com.alexgazin.LaGrillaUITests',PRODUCT_NAME='$(TARGET_NAME)',GENERATE_INFOPLIST_FILE='YES',TEST_TARGET_NAME='LaGrilla')
tests=[build('test:'+str(p.relative_to(ROOT)),ident('file:'+str(p.relative_to(ROOT)))) for p in sorted((ROOT/'UITests').glob('*.swift'))]
test=obj('target:LaGrillaUITests','PBXNativeTarget',buildConfigurationList=configurations('tests',testsettings),buildPhases=[phase('test-sources','PBXSourcesBuildPhase',tests),phase('test-frameworks','PBXFrameworksBuildPhase',[]),phase('test-resources','PBXResourcesBuildPhase',[])],buildRules=[],dependencies=[dep],name='LaGrillaUITests',productName='LaGrillaUITests',productReference=test_product,productType='com.apple.product-type.bundle.ui-testing')
demoref=ident('file:Demos/NativeDemoTests.swift')
demo_settings=dict(base,PRODUCT_BUNDLE_IDENTIFIER='com.alexgazin.LaGrillaDemoTests',PRODUCT_NAME='$(TARGET_NAME)',GENERATE_INFOPLIST_FILE='YES',TEST_TARGET_NAME='LaGrilla')
demo=obj('target:LaGrillaDemoTests','PBXNativeTarget',buildConfigurationList=configurations('demo',demo_settings),buildPhases=[phase('demo-sources','PBXSourcesBuildPhase',[build('demo:NativeDemoTests.swift',demoref)]),phase('demo-frameworks','PBXFrameworksBuildPhase',[]),phase('demo-resources','PBXResourcesBuildPhase',[])],buildRules=[],dependencies=[dep],name='LaGrillaDemoTests',productName='LaGrillaDemoTests',productReference=demo_product,productType='com.apple.product-type.bundle.ui-testing')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'2630','LastUpgradeCheck':'2630','TargetAttributes':{app_id:{'CreatedOnToolsVersion':'16.4'},test_id:{'CreatedOnToolsVersion':'16.4','TestTargetID':app_id},demo_id:{'CreatedOnToolsVersion':'26.3','TestTargetID':app_id}}},buildConfigurationList=configurations('project',base),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ru','Base'],mainGroup=rootgroup,packageReferences=[package],productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=[app,test,demo])
def emit(v,level=0):
 if isinstance(v,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+ ' = '+emit(val,level+1)+';\n' for k,val in v.items())+'\t'*level+'}'
 if isinstance(v,list):return '(\n'+''.join('\t'*(level+1)+emit(x,level+1)+',\n' for x in v)+'\t'*level+')'
 return str(v) if isinstance(v,int) else json.dumps(v,ensure_ascii=False)
pbx=ROOT/'LaGrilla.xcodeproj';pbx.mkdir(exist_ok=True)
(pbx/'project.pbxproj').write_text('// !$*UTF8*$!\n'+emit({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
scheme=ET.Element('Scheme',LastUpgradeVersion='2630',version='1.3')
ba=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES');entries=ET.SubElement(ba,'BuildActionEntries')
def buildable(parent,id,name):ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=id,BuildableName=name,BlueprintName={app_id:'LaGrilla',test_id:'LaGrillaUITests',demo_id:'LaGrillaDemoTests'}[id],ReferencedContainer='container:LaGrilla.xcodeproj')
e=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES');buildable(e,app_id,'LaGrilla.app')
ta=ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES');ts=ET.SubElement(ta,'Testables');te=ET.SubElement(ts,'TestableReference',skipped='NO');buildable(te,test_id,'LaGrillaUITests.xctest')
la=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES');buildable(ET.SubElement(la,'BuildableProductRunnable',runnableDebuggingMode='0'),app_id,'LaGrilla.app')
ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
ET.indent(scheme);folder=pbx/'xcshareddata/xcschemes';folder.mkdir(parents=True,exist_ok=True);ET.ElementTree(scheme).write(folder/'LaGrilla.xcscheme',encoding='utf-8',xml_declaration=True)
print('Generated LaGrilla.xcodeproj:',len(sources),'app source files')

# The authored demo has a separate target/scheme: it never expands release QA's
# functional UITest inventory or silently replaces an acceptance test.
demo_scheme=ET.fromstring(ET.tostring(scheme))
demo_test_action=demo_scheme.find('TestAction');demo_test_action.set('systemAttachmentLifetime','keepAlways')
demo_test_ref=demo_test_action.find('Testables/TestableReference/BuildableReference')
demo_test_ref.set('BlueprintIdentifier',demo_id);demo_test_ref.set('BlueprintName','LaGrillaDemoTests');demo_test_ref.set('BuildableName','LaGrillaDemoTests.xctest')
ET.indent(demo_scheme);ET.ElementTree(demo_scheme).write(folder/'LaGrillaDemo.xcscheme',encoding='utf-8',xml_declaration=True)
