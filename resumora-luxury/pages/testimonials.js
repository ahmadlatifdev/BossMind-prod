/** Testimonials page retired — redirect to pricing. */
export async function getServerSideProps() {
  return {
    redirect: {
      destination: "/pricing",
      permanent: true,
    },
  };
}

export default function TestimonialsPage() {
  return null;
}
