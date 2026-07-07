import type { Metadata } from "next";
import { Header } from "@/components/layout/Header";
import { Footer } from "@/components/layout/Footer";
import { Providers } from "@/components/providers/WagmiProvider";
import "./globals.css";

export const metadata: Metadata = {
  title: "CCIP Lane Checker",
  description:
    "Race tokens across CCIP lanes. Solo challenges and parimutuel betting on testnet.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="font-mono antialiased flex flex-col min-h-screen racing-grid">
        <Providers>
          <Header />
          <main className="flex-1 mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 sm:py-12">
            {children}
          </main>
          <Footer />
        </Providers>
      </body>
    </html>
  );
}
