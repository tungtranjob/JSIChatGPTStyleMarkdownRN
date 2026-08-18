#import <React/RCTViewComponentView.h>
#import <UIKit/UIKit.h>

#import <react/renderer/components/RNMdListSpec/ComponentDescriptors.h>
#import <react/renderer/components/RNMdListSpec/EventEmitters.h>
#import <react/renderer/components/RNMdListSpec/Props.h>
#import <react/renderer/components/RNMdListSpec/RCTComponentViewHelpers.h>

#import <React/RCTConversions.h>

#if __has_include(<RNMdList/RNMdList-Swift.h>)
#import <RNMdList/RNMdList-Swift.h>
#else
#import "RNMdList-Swift.h"
#endif

using namespace facebook::react;

static BOOL MdMessagesEqual(
    const std::vector<MdListViewMessagesStruct> &lhs,
    const std::vector<MdListViewMessagesStruct> &rhs)
{
  if (lhs.size() != rhs.size()) {
    return NO;
  }
  for (size_t i = 0; i < lhs.size(); i++) {
    if (lhs[i].id != rhs[i].id || lhs[i].streaming != rhs[i].streaming ||
        lhs[i].role != rhs[i].role || lhs[i].markdown != rhs[i].markdown) {
      return NO;
    }
  }
  return YES;
}

static NSArray *MdMessagesToArray(const std::vector<MdListViewMessagesStruct> &messages)
{
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:messages.size()];
  for (const auto &message : messages) {
    [result addObject:@{
      @"id" : RCTNSStringFromString(message.id),
      @"role" : RCTNSStringFromString(message.role),
      @"markdown" : RCTNSStringFromString(message.markdown),
      @"streaming" : @(message.streaming),
    }];
  }
  return result;
}

/**
 * Fabric host view. Deliberately thin: it only translates C++ props/commands into
 * the Swift implementation and pushes events back. All rendering logic lives in
 * MdListViewImpl.swift.
 *
 * Declared here rather than in a header on purpose: React Native looks the class
 * up by name (see `codegenConfig.ios.componentProvider`), and keeping this
 * Objective-C++ interface out of the pod's umbrella header is what lets the Swift
 * side compile as a plain Objective-C module.
 */
@interface MdListViewComponentView : RCTViewComponentView <RCTMdListViewViewProtocol>
@end

@implementation MdListViewComponentView {
  MdListViewImpl *_impl;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<MdListViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const MdListViewProps>();
    _props = defaultProps;

    _impl = [[MdListViewImpl alloc] initWithFrame:self.bounds];

    __weak __typeof(self) weakSelf = self;
    _impl.onStartReached = ^(NSString *oldestId) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) {
        return;
      }
      std::static_pointer_cast<const MdListViewEventEmitter>(strongSelf->_eventEmitter)
          ->onStartReached({.oldestId = RCTStringFromNSString(oldestId)});
    };
    _impl.onLinkPress = ^(NSString *url) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) {
        return;
      }
      std::static_pointer_cast<const MdListViewEventEmitter>(strongSelf->_eventEmitter)
          ->onLinkPress({.url = RCTStringFromNSString(url)});
    };
    _impl.onCodeCopy = ^(NSString *code, NSString *language) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) {
        return;
      }
      std::static_pointer_cast<const MdListViewEventEmitter>(strongSelf->_eventEmitter)
          ->onCodeCopy({
              .language = RCTStringFromNSString(language),
              .code = RCTStringFromNSString(code),
          });
    };
    _impl.onAtBottomChange = ^(BOOL atBottom) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) {
        return;
      }
      std::static_pointer_cast<const MdListViewEventEmitter>(strongSelf->_eventEmitter)
          ->onAtBottomChange({.atBottom = static_cast<bool>(atBottom)});
    };
    _impl.onVisibleRangeChange = ^(NSInteger first, NSInteger last, NSInteger count) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) {
        return;
      }
      std::static_pointer_cast<const MdListViewEventEmitter>(strongSelf->_eventEmitter)
          ->onVisibleRangeChange({
              .firstIndex = static_cast<int>(first),
              .lastIndex = static_cast<int>(last),
              .blockCount = static_cast<int>(count),
          });
    };

    self.contentView = _impl;
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<const MdListViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const MdListViewProps>(props);

  if (oldViewProps.colorScheme != newViewProps.colorScheme) {
    [_impl setColorScheme:RCTNSStringFromString(newViewProps.colorScheme)];
  }
  if (oldViewProps.fontSize != newViewProps.fontSize) {
    [_impl setFontSize:newViewProps.fontSize];
  }
  if (oldViewProps.topInset != newViewProps.topInset) {
    [_impl setTopInset:newViewProps.topInset];
  }
  if (oldViewProps.bottomInset != newViewProps.bottomInset) {
    [_impl setBottomInset:newViewProps.bottomInset];
  }
  if (oldViewProps.loadingOlder != newViewProps.loadingOlder) {
    [_impl setLoadingOlder:newViewProps.loadingOlder];
  }
  if (oldViewProps.startReachedThreshold != newViewProps.startReachedThreshold) {
    [_impl setStartReachedThreshold:newViewProps.startReachedThreshold];
  }
  if (oldViewProps.prefetchRows != newViewProps.prefetchRows) {
    [_impl setPrefetchRows:newViewProps.prefetchRows];
  }
  if (oldViewProps.autoScrollToBottom != newViewProps.autoScrollToBottom) {
    [_impl setAutoScrollToBottom:newViewProps.autoScrollToBottom];
  }
  // Exact comparison rather than a hash: memcmp over the transcript is cheap and
  // means a streaming update never re-crosses the bridge as a no-op.
  if (!MdMessagesEqual(oldViewProps.messages, newViewProps.messages)) {
    [_impl setMessages:MdMessagesToArray(newViewProps.messages)];
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)prepareForRecycle
{
  [_impl reset];
  [super prepareForRecycle];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTMdListViewHandleCommand(self, commandName, args);
}

- (void)scrollToBottom:(BOOL)animated
{
  [_impl scrollToBottomAnimated:animated];
}

- (void)scrollToMessage:(NSString *)messageId animated:(BOOL)animated
{
  [_impl scrollToMessage:messageId animated:animated];
}

@end
