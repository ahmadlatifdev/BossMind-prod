import Link from 'next/link'

export default function Header() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-black/95 backdrop-blur-sm border-b border-gold-500/20">
      <div className="container mx-auto px-6 py-4">
        <Link href="/" className="block">
          <span className="text-2xl font-bold text-white tracking-wider">
            RESUMORA
            <span className="text-gold-500">.</span>
          </span>
        </Link>
      </div>
    </header>
  )
}
