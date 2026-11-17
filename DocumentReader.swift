import UIKit

final class DocumentReader: UIView {
    private let heading = UILabel()
    private let byline = UILabel()
    private let bodyText = UILabel()
    private let sheet = UIView()
    private let scroll = UIScrollView()
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame:frame)
        isHidden = true
        accessibilityViewIsModal = true
        backgroundColor = UIColor(white:0.01,alpha:0.80)
        sheet.backgroundColor = UIColor(red:0.88,green:0.82,blue:0.69,alpha:1)
        sheet.layer.cornerRadius = 3
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.72
        sheet.layer.shadowRadius = 24
        sheet.layer.shadowOffset = CGSize(width:0,height:10)
        sheet.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sheet)

        let close = UIButton(type:.system)
        close.setTitle("Done",for:.normal)
        close.tintColor = UIColor(red:0.26,green:0.13,blue:0.07,alpha:1)
        close.titleLabel?.font = .systemFont(ofSize:16,weight:.semibold)
        close.addTarget(self,action:#selector(dismissPage),for:.touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(close)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(scroll)
        let text = UIStackView(arrangedSubviews:[byline,heading,bodyText])
        text.axis = .vertical
        text.spacing = 14
        text.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(text)

        byline.font = .monospacedSystemFont(ofSize:12,weight:.semibold)
        byline.textColor = UIColor(red:0.39,green:0.24,blue:0.15,alpha:1)
        byline.numberOfLines = 0
        heading.font = .systemFont(ofSize:30,weight:.bold)
        heading.textColor = UIColor(red:0.17,green:0.12,blue:0.08,alpha:1)
        heading.numberOfLines = 0
        heading.accessibilityTraits = [.header]
        bodyText.textColor = heading.textColor
        bodyText.numberOfLines = 0
        bodyText.font = UIFont(name:"Georgia",size:19) ?? .systemFont(ofSize:19)
        bodyText.adjustsFontForContentSizeCategory = true
        bodyText.font = UIFontMetrics(forTextStyle:.body).scaledFont(for:bodyText.font)

        let safe = safeAreaLayoutGuide
        let preferredWidth = sheet.widthAnchor.constraint(equalTo:safe.widthAnchor,multiplier:0.80)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            sheet.widthAnchor.constraint(lessThanOrEqualToConstant:550),
            sheet.heightAnchor.constraint(equalTo:safe.heightAnchor,multiplier:0.84),
            sheet.centerXAnchor.constraint(equalTo:safe.centerXAnchor),
            sheet.centerYAnchor.constraint(equalTo:safe.centerYAnchor),
            close.trailingAnchor.constraint(equalTo:sheet.trailingAnchor,constant:-18),
            close.topAnchor.constraint(equalTo:sheet.topAnchor,constant:6),
            close.heightAnchor.constraint(equalToConstant:44),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant:54),
            scroll.topAnchor.constraint(equalTo:close.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo:sheet.bottomAnchor,constant:-18),
            scroll.leadingAnchor.constraint(equalTo:sheet.leadingAnchor,constant:26),
            scroll.trailingAnchor.constraint(equalTo:sheet.trailingAnchor,constant:-26),
            text.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),
            text.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),
            text.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),
            text.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:6),
            text.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-10)
        ])
    }

    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(title:String, by author:String, body:String) {
        heading.text = title
        byline.text = author.uppercased()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        bodyText.attributedText = NSAttributedString(string:body,attributes:[.paragraphStyle:paragraph])
        isHidden = false
        scroll.setContentOffset(.zero, animated:false)
        alpha = 0
        if !UIAccessibility.isReduceMotionEnabled {
            sheet.transform = CGAffineTransform(translationX:0,y:20).scaledBy(x:0.98,y:0.98)
        }
        UIView.animate(withDuration:0.20) {
            self.alpha = 1
            self.sheet.transform = .identity
        }
        UIAccessibility.post(notification:.screenChanged,argument:heading)
    }

    @objc private func dismissPage() { onClose?() }

    override func accessibilityPerformEscape() -> Bool {
        dismissPage()
        return true
    }
}
