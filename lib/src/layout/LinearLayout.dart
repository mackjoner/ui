//Copyright (C) 2012 Potix Corporation. All Rights Reserved.
//History: Thu, Mar 15, 2012  4:48:10 PM
// Author: tomyeh

/**
 * The linear layout. It arranges the children of the associated view in
 * a single column or a single row. The direction is controlled by
 * [LayoutDeclaration.orient]. If not specified, it is default to `horizontal`.
 */
class LinearLayout extends AbstractLayout {
  static _RealLinearLayout _getRealLayout(view) //horizontal is default
  => view.layout.orient != "vertical" ? new _HLayout(): new _VLayout();

  int measureWidth(MeasureContext mctx, View view)
  => _getRealLayout(view).measureWidth(mctx, view);
  int measureHeight(MeasureContext mctx, View view)
  => _getRealLayout(view).measureHeight(mctx, view);

  void doLayout_(MeasureContext mctx, View view, List<View> children)
  => _getRealLayout(view).doLayout(mctx, view, children);
}

interface _RealLinearLayout {
  int measureWidth(MeasureContext mctx, View view);
  int measureHeight(MeasureContext mctx, View view);
  void doLayout(MeasureContext mctx, View view, List<View> children);
}

/**
 * Horizontal linear layout.
 */
class _HLayout implements _RealLinearLayout {
  int measureWidth(MeasureContext mctx, View view) {
    final int va = mctx.getWidthByApp(view);
    if (va != null)
      return va;

    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final gapinf = new LayoutSideInfo(view.layout.gap);
    final defpwd = view.layout.width;
    int width = 0, prevSpacing;
    for (final View child in view.children) {
      if (!view.shallLayout_(child) || child.profile.anchorView != null)
        continue; //ignore anchored

      //add spacing to width
      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      width += prevSpacing == null ? si.left: //first
        gapinf.left != null ? gapinf.left: max(prevSpacing, si.left);
      prevSpacing = si.right;

      final pwd = child.profile.width;
      final amt = _getLayoutAmountInfo(child, pwd.isEmpty ? defpwd: pwd);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          width += amt.value;
          break;
        case LayoutAmountType.NONE:
        case LayoutAmountType.CONTENT:
          final int wapp = mctx.getWidthByApp(child);
          final int wd = wapp != null && amt.type != LayoutAmountType.CONTENT ? 
              wapp : child.measureWidth_(mctx);
          width += wd != null ? wd: child.realWidth;
          break;
        //default: if flex/%, don't count
      }
    }

    width += mctx.getBorderWidth(view)
      + (prevSpacing != null ? prevSpacing: spcinf.left + spcinf.right);
    return width;
  }
  int measureHeight(MeasureContext mctx, View view) {
    final int va = mctx.getHeightByApp(view);
    if (va != null)
      return va;

    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final String defphgh = view.layout.height;
    final int borderHgh = mctx.getBorderHeight(view);
    int height;
    for (final View child in view.children) {
      if (!view.shallLayout_(child) || child.profile.anchorView != null)
        continue; //ignore anchored

      //add spacing to width
      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      int hgh = si.top + si.bottom + borderHgh; //spacing of border
      final phgh = child.profile.height;
      final amt = _getLayoutAmountInfo(child, phgh.isEmpty ? defphgh: phgh);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          hgh += amt.value;
          break;
        case LayoutAmountType.NONE:
        case LayoutAmountType.CONTENT:
          final happ = mctx.getHeightByApp(child);
          final int h = happ != null && amt.type != LayoutAmountType.CONTENT ? 
              happ : child.measureHeight_(mctx);
          hgh += h != null ? h: child.realHeight;
          break;
        default:
          continue; //ignore if flex or ratio is used
      }

      if (height == null || hgh > height)
        height = hgh;
    }
    return height;
  }
  //children contains only indepedent views
  void doLayout(MeasureContext mctx, View view, List<View> children) {
    //1) size
    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final gapinf = new LayoutSideInfo(view.layout.gap);
    final String defpwd = view.layout.width;
    final Map<View, LayoutSideInfo> childspcinfs = new Map();
    final List<View> flexViews = new List();
    final List<int> flexs = new List();
    int nflex = 0, assigned = 0, prevSpacing;
    for (final View child in children) {
      if (!view.shallLayout_(child)) {
        mctx.setWidthByProfile(child, () => view.innerWidth);
        mctx.setHeightByProfile(child, () => view.innerHeight);
        continue;
      }

      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      childspcinfs[child] = si;
      assigned += prevSpacing == null ? si.left: //first
        gapinf.left != null ? gapinf.left: max(prevSpacing, si.left);
      prevSpacing = si.right;

      final pwd = child.profile.width;
      final amt = _getLayoutAmountInfo(child, pwd.isEmpty ? defpwd: pwd);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          assigned += child.width = amt.value;
          break;
        case LayoutAmountType.FLEX:
          nflex += amt.value;
          flexs.add(amt.value);
          flexViews.add(child);
          break;
        case LayoutAmountType.RATIO:
          assigned += child.width = (view.innerWidth * amt.value).round().toInt();
          break;
        default:
          int wdapp;
          if (amt.type == LayoutAmountType.NONE
          && (wdapp = mctx.getWidthByApp(child)) != null)
            assigned += wdapp;
          else {
            final int wd = child.measureWidth_(mctx);
            if (wd != null)
              assigned += child.width = wd;
            else
              assigned += child.realWidth;
          }
          break;
      }

      mctx.setHeightByProfile(child,
        () => view.innerHeight - si.top - si.bottom); //subtract spacing from borders
    }

    //1a) size flex
    if (nflex > 0) {
      int space = view.innerWidth - assigned - prevSpacing; //prevSpacing not null here
      double per = space / nflex;
      for (int j = 0, len = flexs.length - 1;; ++j) {
        if (j == len) { //last
          flexViews[j].width = space;
          break;
        }
        final int delta = (per * flexs[j]).round().toInt();
        flexViews[j].width = delta;
        space -= delta;
      }
    }

    //2) position
    final String defAlign = view.layout.align;
    prevSpacing = null;
    assigned = 0;
    for (final View child in children) {
      if (!view.shallLayout_(child))
        continue;

      final si = childspcinfs[child];
      child.left = assigned += prevSpacing == null ? si.left: //first
        gapinf.left != null ? gapinf.left: max(prevSpacing, si.left);
      assigned += child.realWidth;
      prevSpacing = si.right;

      String align = child.profile.align;
      if (align.isEmpty) align = defAlign;
      final int space = childspcinfs[child].top;
      switch (align) {
        case "center":
        case "end":
          int delta = view.innerHeight - si.top - si.bottom - child.realHeight;
          if (align == "center") delta ~/= 2;
          child.top = space + delta;
          break; 
        default:
          child.top = space;
      }
    }
  }
}

/**
 * Vertical linear layout.
 */
class _VLayout implements _RealLinearLayout {
  int measureHeight(MeasureContext mctx, View view) {
    final int va = mctx.getHeightByApp(view);
    if (va != null)
      return va;

    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final gapinf = new LayoutSideInfo(view.layout.gap);
    final defphgh = view.layout.height;
    int height = 0, prevSpacing;
    for (final View child in view.children) {
      if (!view.shallLayout_(child) || child.profile.anchorView != null)
        continue; //ignore anchored

      //add spacing to height
      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      height += prevSpacing == null ? si.top: //first
        gapinf.top != null ? gapinf.top: max(prevSpacing, si.top);
      prevSpacing = si.bottom;

      final phgh = child.profile.height;
      final amt = _getLayoutAmountInfo(child, phgh.isEmpty ? defphgh: phgh);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          height += amt.value;
          break;
        case LayoutAmountType.NONE:
        case LayoutAmountType.CONTENT:
          final happ = mctx.getHeightByApp(child);
          final int hgh = happ != null && amt.type != LayoutAmountType.CONTENT ? 
              happ : child.measureHeight_(mctx);
          height += hgh != null ? hgh: child.realHeight;
          break;
        //default: if flex/%, don't count
      }
    }

    height += mctx.getBorderHeight(view)
      + (prevSpacing != null ? prevSpacing: spcinf.top + spcinf.bottom);
    return height;
  }
  int measureWidth(MeasureContext mctx, View view) {
    final int va = mctx.getWidthByApp(view);
    if (va != null)
      return va;

    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final defpwd = view.layout.width;
    final int borderWd = mctx.getBorderWidth(view);
    int width;
    for (final View child in view.children) {
      if (!view.shallLayout_(child) || child.profile.anchorView != null)
        continue; //ignore anchored

      //add spacing to height
      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      int wd = si.left + si.right + borderWd; //spacing of border
      final pwd = child.profile.width;
      final amt = _getLayoutAmountInfo(child, pwd.isEmpty ? defpwd: pwd);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          wd += amt.value;
          break;
        case LayoutAmountType.NONE:
        case LayoutAmountType.CONTENT:
          final int wapp = mctx.getWidthByApp(child);
          final int w = wapp != null && amt.type != LayoutAmountType.CONTENT ? 
              wapp : child.measureWidth_(mctx);
          wd += w != null ? w: child.realWidth;
          break;
        default:
          continue; //ignore if flex or ratio is used
      }

      if (width == null || wd > width)
        width = wd;
    }
    return width;
  }
  //children contains only indepedent views
  void doLayout(MeasureContext mctx, View view, List<View> children) {
    //1) size
    final spcinf = new LayoutSideInfo(view.layout.spacing, _DEFAULT_SPACING);
    final gapinf = new LayoutSideInfo(view.layout.gap);
    final defphgh = view.layout.height;
    final Map<View, LayoutSideInfo> childspcinfs = new Map();
    final List<View> flexViews = new List();
    final List<int> flexs = new List();
    int nflex = 0, assigned = 0, prevSpacing;
    for (final View child in children) {
      if (!view.shallLayout_(child)) {
        mctx.setWidthByProfile(child, () => view.innerWidth);
        mctx.setHeightByProfile(child, () => view.innerHeight);
        continue;
      }

      final si = new LayoutSideInfo(child.profile.spacing, 0, spcinf);
      childspcinfs[child] = si;
      assigned += prevSpacing == null ? si.top: //first
        gapinf.top != null ? gapinf.top: max(prevSpacing, si.top);
      prevSpacing = si.bottom;

      final phgh = child.profile.height;
      final amt = _getLayoutAmountInfo(child, phgh.isEmpty ? defphgh: phgh);
      switch (amt.type) {
        case LayoutAmountType.FIXED:
          assigned += child.height = amt.value;
          break;
        case LayoutAmountType.FLEX:
          nflex += amt.value;
          flexs.add(amt.value);
          flexViews.add(child);
          break;
        case LayoutAmountType.RATIO:
          assigned += child.height = (view.innerHeight * amt.value).round().toInt();
          break;
        default:
          int hghapp;
          if (amt.type == LayoutAmountType.NONE
          && (hghapp = mctx.getHeightByApp(child)) != null)
            assigned += hghapp;
          else {
            final int hgh = child.measureHeight_(mctx);
            if (hgh != null)
              assigned += child.height = hgh;
            else
              assigned += child.realHeight;
          }
          break;
      }

      mctx.setWidthByProfile(child,
        () => view.innerWidth - si.left - si.right); //subtract spacing from border
    }

    //1a) size flex
    if (nflex > 0) {
      int space = view.innerHeight - assigned - prevSpacing; //prevSpacing must not null
      double per = space / nflex;
      for (int j = 0, len = flexs.length - 1;; ++j) {
        if (j == len) { //last
          flexViews[j].height = space;
          break;
        }
        final int delta = (per * flexs[j]).round().toInt();
        flexViews[j].height = delta;
        space -= delta;
      }
    }

    //2) position
    final defAlign = view.layout.align;
    prevSpacing = null;
    assigned = 0;
    for (final View child in children) {
      if (!view.shallLayout_(child))
        continue;

      final si = childspcinfs[child];
      child.top = assigned += prevSpacing == null ? si.top: //first
        gapinf.top != null ? gapinf.top: max(prevSpacing, si.top);
      assigned += child.realHeight;
      prevSpacing = si.bottom;

      String align = child.profile.align;
      if (align.isEmpty) align = defAlign;
      final int space = childspcinfs[child].left;
      switch (align) {
        case "center":
        case "end":
          int delta = view.innerWidth - si.left - si.right - child.realWidth;
          if (align == "center") delta ~/= 2;
          child.left = space + delta;
          break; 
        default:
          child.left = space;
      }
    }
  }
}
